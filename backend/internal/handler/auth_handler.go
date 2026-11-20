// Package handler 提供 HTTP Handler 层
package handler

import (
	"meeting-platform/internal/middleware"
	"meeting-platform/internal/service"
	"meeting-platform/pkg/response"

	"github.com/gin-gonic/gin"
)

// AuthHandler 鉴权相关 Handler
type AuthHandler struct {
	authService *service.AuthService
}

// NewAuthHandler 创建 AuthHandler
func NewAuthHandler(authService *service.AuthService) *AuthHandler {
	return &AuthHandler{authService: authService}
}

// Register POST /api/v1/auth/register
func (h *AuthHandler) Register(c *gin.Context) {
	var req service.RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}
	user, err := h.authService.Register(&req)
	if err != nil {
		response.Fail(c, 10001, err.Error())
		return
	}
	response.Created(c, gin.H{
		"id":         user.ID,
		"email":      user.Email,
		"name":       user.Name,
		"role":       user.RoleName,
		"avatar_url": user.AvatarURL,
	})
}

// Login POST /api/v1/auth/login
func (h *AuthHandler) Login(c *gin.Context) {
	var req service.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}
	tokens, user, err := h.authService.Login(&req)
	if err != nil {
		response.Fail(c, 10002, err.Error())
		return
	}
	response.OK(c, gin.H{
		"tokens": tokens,
		"user": gin.H{
			"id":         user.ID,
			"email":      user.Email,
			"name":       user.Name,
			"role":       user.RoleName,
			"avatar_url": user.AvatarURL,
		},
	})
}

// Refresh POST /api/v1/auth/refresh
func (h *AuthHandler) Refresh(c *gin.Context) {
	var body struct {
		RefreshToken string `json:"refresh_token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.BadRequest(c, err.Error())
		return
	}
	tokens, err := h.authService.Refresh(body.RefreshToken)
	if err != nil {
		response.Unauthorized(c, err.Error())
		return
	}
	response.OK(c, tokens)
}

// Me GET /api/v1/auth/me — 返回当前登录用户信息
func (h *AuthHandler) Me(c *gin.Context) {
	claims := middleware.GetClaims(c)
	if claims == nil {
		response.Unauthorized(c, "unauthorized")
		return
	}
	// 查库取最新头像（JWT 中不携带 avatar）
	user, err := h.authService.GetUserByID(claims.UserID)
	if err != nil {
		response.NotFound(c, "user")
		return
	}
	response.OK(c, gin.H{
		"id":         claims.UserID,
		"email":      claims.Email,
		"name":       claims.Name,
		"role":       claims.Role,
		"avatar_url": user.AvatarURL,
	})
}

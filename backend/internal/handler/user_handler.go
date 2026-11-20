package handler

import (
	"meeting-platform/internal/middleware"
	"meeting-platform/internal/service"
	"strconv"

	"github.com/gin-gonic/gin"
)

// UserHandler 管理员用户管理
type UserHandler struct {
	svc *service.UserAdminService
}

// NewUserHandler 创建
func NewUserHandler(svc *service.UserAdminService) *UserHandler { return &UserHandler{svc: svc} }

// Create POST /api/v1/users —— 管理员创建账号
func (h *UserHandler) Create(c *gin.Context) {
	var req service.CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}
	u, err := h.svc.CreateUser(&req)
	if err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}
	c.JSON(201, u)
}

// List GET /api/v1/users —— 带分页/搜索/角色过滤
func (h *UserHandler) List(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	search := c.Query("search")
	role := c.Query("role")
	list, total, err := h.svc.ListUsers(page, pageSize, search, role)
	if err != nil {
		c.JSON(500, gin.H{"error": err.Error()})
		return
	}
	c.JSON(200, gin.H{
		"items": list, "total": total, "page": page, "page_size": pageSize,
	})
}

// UpdateRoleOrStatus PATCH /api/v1/users/:id
func (h *UserHandler) UpdateRoleOrStatus(c *gin.Context) {
	claims := middleware.GetClaims(c)
	var req struct {
		Role   string `json:"role"`
		Status string `json:"status"`
	}
	c.ShouldBindJSON(&req)
	// 不允许把自己改成 disabled（防止锁死自己）
	if claims.UserID == c.Param("id") && req.Status == "disabled" {
		c.JSON(400, gin.H{"error": "cannot disable yourself"})
		return
	}
	if err := h.svc.UpdateRoleOrStatus(c.Param("id"), req.Role, req.Status); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}
	c.JSON(200, gin.H{"ok": true})
}

// Delete DELETE /api/v1/users/:id —— 软删除
func (h *UserHandler) Delete(c *gin.Context) {
	claims := middleware.GetClaims(c)
	if claims.UserID == c.Param("id") {
		c.JSON(400, gin.H{"error": "cannot delete yourself"})
		return
	}
	if err := h.svc.DeleteUser(c.Param("id")); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}
	c.JSON(200, gin.H{"ok": true})
}

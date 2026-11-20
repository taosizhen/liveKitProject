package handler

import (
	"fmt"
	"meeting-platform/internal/middleware"
	"meeting-platform/internal/service"
	"meeting-platform/pkg/response"
	"meeting-platform/pkg/storage"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// UserHandler 管理员用户管理 + 当前用户自助（头像上传）
type UserHandler struct {
	svc     *service.UserAdminService
	storage *storage.Service
}

// NewUserHandler 创建
func NewUserHandler(svc *service.UserAdminService, st *storage.Service) *UserHandler {
	return &UserHandler{svc: svc, storage: st}
}

// UploadAvatar POST /api/v1/profile/avatar —— 当前用户上传头像（登录即可，非 admin）
// multipart 字段名为 file；存到 storage 的 avatars 子目录，并回写 user.avatar_url
func (h *UserHandler) UploadAvatar(c *gin.Context) {
	claims := middleware.GetClaims(c)
	if claims == nil {
		response.Unauthorized(c, "unauthorized")
		return
	}
	file, header, err := c.Request.FormFile("file")
	if err != nil {
		response.BadRequest(c, "file required")
		return
	}
	file.Close() // 由 storage.Save 内部重新打开

	// 仅允许常见图片格式
	ext := strings.ToLower(filepath.Ext(header.Filename))
	if !map[string]bool{".jpg": true, ".jpeg": true, ".png": true, ".webp": true, ".gif": true}[ext] {
		response.BadRequest(c, "only jpg/jpeg/png/webp/gif allowed")
		return
	}

	rel, _, err := h.storage.Save("avatars", header)
	if err != nil {
		response.ServerError(c, fmt.Errorf("save avatar: %w", err))
		return
	}
	url := "/storage/" + rel
	if err := h.svc.UpdateAvatarURL(claims.UserID, url); err != nil {
		response.ServerError(c, err)
		return
	}
	response.OK(c, gin.H{"avatar_url": url})
}

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

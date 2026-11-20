package handler

import (
	"meeting-platform/internal/middleware"
	"meeting-platform/internal/service"
	"meeting-platform/pkg/response"
	"meeting-platform/pkg/storage"
	"net/http"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
)

// MaterialHandler 会议材料
type MaterialHandler struct {
	svc    *service.MaterialService
	storage *storage.Service
}

// NewMaterialHandler 创建
func NewMaterialHandler(svc *service.MaterialService, st *storage.Service) *MaterialHandler {
	return &MaterialHandler{svc: svc, storage: st}
}

// Upload POST /api/v1/meetings/:id/materials —— multipart 文件上传
func (h *MaterialHandler) Upload(c *gin.Context) {
	claims := middleware.GetClaims(c)
	meetingID := c.Param("id")
	file, header, err := c.Request.FormFile("file")
	if err != nil {
		response.BadRequest(c, "file required")
		return
	}
	file.Close() // 让 service 内部从 header 打开

	m, err := h.svc.SaveAndCreate(claims.UserID, meetingID, header)
	if err != nil {
		response.Fail(c, 30001, err.Error())
		return
	}
	response.Created(c, m)
}

// List GET /api/v1/meetings/:id/materials
func (h *MaterialHandler) List(c *gin.Context) {
	claims := middleware.GetClaims(c)
	list, err := h.svc.ListByMeeting(claims.UserID, c.Param("id"))
	if err != nil {
		response.Fail(c, 30002, err.Error())
		return
	}
	response.OK(c, list)
}

// Delete DELETE /api/v1/materials/:id
func (h *MaterialHandler) Delete(c *gin.Context) {
	claims := middleware.GetClaims(c)
	if err := h.svc.Delete(claims.UserID, c.Param("id")); err != nil {
		response.Fail(c, 30003, err.Error())
		return
	}
	response.OK(c, nil)
}

// Download GET /storage/... —— 静态文件下载/预览（注册为 gin handler 时前缀为 /storage）
func (h *MaterialHandler) Download(c *gin.Context) {
	// 路径在 gin 中会带 /storage 前缀，需去除
	rel := strings.TrimPrefix(c.Request.URL.Path, "/storage/")
	fullPath := h.storage.FullPath(rel)

	// 安全校验：最终路径必须在 storage.Root() 下
	root, _ := filepath.Abs(h.storage.Root())
	abs, _ := filepath.Abs(fullPath)
	if !strings.HasPrefix(abs, root) {
		response.Forbidden(c, "path traversal rejected")
		return
	}

	if _, err := c.Request.Body.Read([]byte{}); err == nil {
		// no-op
	}

	if _, err := filepath.Abs(fullPath); err != nil {
		response.NotFound(c, "file")
		return
	}

	c.Header("Content-Disposition", "inline")
	c.File(fullPath)
	_ = http.StatusOK
}

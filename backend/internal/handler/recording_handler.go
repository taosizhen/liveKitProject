package handler

import (
	"strconv"

	"meeting-platform/internal/middleware"
	"meeting-platform/internal/service"
	"meeting-platform/pkg/response"

	"github.com/gin-gonic/gin"
)

// RecordingHandler 会议录制
type RecordingHandler struct {
	svc *service.RecordingService
}

// NewRecordingHandler 创建
func NewRecordingHandler(svc *service.RecordingService) *RecordingHandler { return &RecordingHandler{svc: svc} }

// Register POST /api/v1/meetings/:id/recordings —— 客户端上报录制元数据
func (h *RecordingHandler) Register(c *gin.Context) {
	claims := middleware.GetClaims(c)
	meetingID := c.Param("id")

	var req service.RegisterRecordingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Fail(c, 40001, err.Error())
		return
	}
	req.MeetingID = meetingID

	rec, err := h.svc.RegisterRecording(claims.UserID, &req)
	if err != nil {
		response.Fail(c, 20010, err.Error())
		return
	}
	response.OK(c, rec)
}

// Upload POST /api/v1/meetings/:id/recordings/upload —— 上传浏览器录制文件（multipart）
func (h *RecordingHandler) Upload(c *gin.Context) {
	claims := middleware.GetClaims(c)
	meetingID := c.Param("id")

	file, header, err := c.Request.FormFile("file")
	if err != nil {
		response.BadRequest(c, "file required")
		return
	}
	file.Close()

	durationSec, _ := strconv.Atoi(c.PostForm("duration_sec"))
	rec, err := h.svc.UploadRecording(claims.UserID, meetingID, header, durationSec)
	if err != nil {
		response.Fail(c, 20014, err.Error())
		return
	}
	response.Created(c, rec)
}

// Complete PATCH /api/v1/recordings/:id/complete
func (h *RecordingHandler) Complete(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		RecordingID string `json:"recording_id"`
		DurationSec int    `json:"duration_sec"`
	}
	c.ShouldBindJSON(&req)
	if err := h.svc.CompleteRecording(id, req.RecordingID, req.DurationSec); err != nil {
		response.Fail(c, 20011, err.Error())
		return
	}
	response.OK(c, gin.H{"ok": true})
}

// List GET /api/v1/meetings/:id/recordings —— 会议录制回放列表
func (h *RecordingHandler) List(c *gin.Context) {
	claims := middleware.GetClaims(c)
	list, err := h.svc.ListByMeeting(claims.UserID, c.Param("id"))
	if err != nil {
		response.Fail(c, 20012, err.Error())
		return
	}
	response.OK(c, list)
}

// Delete DELETE /api/v1/recordings/:id
func (h *RecordingHandler) Delete(c *gin.Context) {
	claims := middleware.GetClaims(c)
	if err := h.svc.DeleteRecording(claims.UserID, c.Param("id")); err != nil {
		response.Fail(c, 20013, err.Error())
		return
	}
	response.OK(c, gin.H{"ok": true})
}

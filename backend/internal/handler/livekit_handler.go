package handler

import (
	"fmt"
	"meeting-platform/internal/middleware"
	"meeting-platform/internal/service"
	"meeting-platform/internal/service/livekitutil"
	"meeting-platform/pkg/response"

	"github.com/gin-gonic/gin"
)

// LiveKitHandler LiveKit 集成 Handler
type LiveKitHandler struct {
	meetingService *service.MeetingService
	livekitSvc     *livekitutil.Service
	livekitURL     string
}

// NewLiveKitHandler 创建 LiveKitHandler
func NewLiveKitHandler(ms *service.MeetingService, livekitURL string, livekitSvc *livekitutil.Service) *LiveKitHandler {
	return &LiveKitHandler{
		meetingService: ms,
		livekitURL:     livekitURL,
		livekitSvc:     livekitSvc,
	}
}

// GetJoinToken GET /api/v1/meetings/:id/livekit-token
// 返回 LiveKit 连接信息：ws URL + Join Token + Room Name
func (h *LiveKitHandler) GetJoinToken(c *gin.Context) {
	claims := middleware.GetClaims(c)
	meetingID := c.Param("id")

	// 1. 校验会议访问权限
	meeting, err := h.meetingService.GetMeeting(claims.UserID, meetingID)
	if err != nil {
		if err.Error() == "forbidden: not a meeting participant" {
			response.Forbidden(c, err.Error())
		} else {
			response.NotFound(c, "meeting")
		}
		return
	}

	// 2. 标记用户加入会议
	_ = h.meetingService.JoinMeeting(claims.UserID, meetingID)

	// 3. 生成 LiveKit Token（metadata 携带角色与头像，供会议内动态主持人判定与头像显示）
	canPublish, canRecord := livekitutil.GetParticipantPermission(claims.Role)
	avatarURL := h.meetingService.GetUserAvatarURL(claims.UserID)
	token, err := h.livekitSvc.GenerateJoinToken(
		meeting.RoomName,
		claims.UserID,
		claims.Name,
		claims.Role,
		avatarURL,
		canPublish,
		canRecord,
	)
	if err != nil {
		response.ServerError(c, fmt.Errorf("livekit token: %w", err))
		return
	}

	// 4. 返回连接信息
	response.OK(c, gin.H{
		"livekit_url": h.livekitURL,
		"token":       token,
		"room_name":   meeting.RoomName,
		"meeting_id":  meeting.ID.String(),
	})
}

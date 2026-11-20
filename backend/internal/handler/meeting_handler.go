package handler

import (
	"meeting-platform/internal/middleware"
	"meeting-platform/internal/repository"
	"meeting-platform/internal/service"
	"meeting-platform/pkg/response"
	"strconv"

	"github.com/gin-gonic/gin"
)

// MeetingHandler 会议相关 Handler
type MeetingHandler struct {
	meetingService *service.MeetingService
	livekitURL     string
}

// NewMeetingHandler 创建 MeetingHandler
func NewMeetingHandler(ms *service.MeetingService, livekitURL string) *MeetingHandler {
	return &MeetingHandler{meetingService: ms, livekitURL: livekitURL}
}

// Create POST /api/v1/meetings
func (h *MeetingHandler) Create(c *gin.Context) {
	claims := middleware.GetClaims(c)
	var req service.CreateMeetingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}
	meeting, err := h.meetingService.CreateMeeting(claims.UserID, &req)
	if err != nil {
		response.Fail(c, 20001, err.Error())
		return
	}
	response.Created(c, meeting)
}

// List GET /api/v1/meetings
func (h *MeetingHandler) List(c *gin.Context) {
	claims := middleware.GetClaims(c)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	status := c.Query("status")

	meetings, total, err := h.meetingService.ListMeetings(claims.UserID, page, pageSize, status)
	if err != nil {
		response.ServerError(c, err)
		return
	}
	response.Paginated(c, meetings, total, page, pageSize)
}

// Get GET /api/v1/meetings/:id
func (h *MeetingHandler) Get(c *gin.Context) {
	claims := middleware.GetClaims(c)
	meetingID := c.Param("id")
	meeting, err := h.meetingService.GetMeeting(claims.UserID, meetingID)
	if err != nil {
		if err.Error() == "forbidden: not a meeting participant" {
			response.Forbidden(c, err.Error())
		} else {
			response.NotFound(c, "meeting")
		}
		return
	}
	response.OK(c, meeting)
}

// Cancel DELETE /api/v1/meetings/:id
func (h *MeetingHandler) Cancel(c *gin.Context) {
	claims := middleware.GetClaims(c)
	meetingID := c.Param("id")
	if err := h.meetingService.CancelMeeting(claims.UserID, meetingID); err != nil {
		response.Fail(c, 20002, err.Error())
		return
	}
	response.OK(c, nil)
}

// Join POST /api/v1/meetings/:id/join — 用户确认加入会议
func (h *MeetingHandler) Join(c *gin.Context) {
	claims := middleware.GetClaims(c)
	meetingID := c.Param("id")
	if err := h.meetingService.JoinMeeting(claims.UserID, meetingID); err != nil {
		response.Fail(c, 20003, err.Error())
		return
	}
	response.OK(c, gin.H{"status": "joined"})
}

// Invite POST /api/v1/meetings/:id/invite — 组织者邀请参会者
func (h *MeetingHandler) Invite(c *gin.Context) {
	claims := middleware.GetClaims(c)
	meetingID := c.Param("id")
	var req struct {
		ParticipantIDs []string `json:"participant_ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "participant_ids required")
		return
	}
	added, err := h.meetingService.InviteParticipants(claims.UserID, meetingID, req.ParticipantIDs)
	if err != nil {
		response.Fail(c, 20004, err.Error())
		return
	}
	response.OK(c, gin.H{"added": added})
}

// Purge DELETE /api/v1/meetings/:id/permanent — 彻底删除已结束会议（含录制与材料）
func (h *MeetingHandler) Purge(c *gin.Context) {
	claims := middleware.GetClaims(c)
	meetingID := c.Param("id")
	result, err := h.meetingService.PurgeMeeting(claims.UserID, claims.Role, meetingID)
	if err != nil {
		response.Fail(c, 20005, err.Error())
		return
	}
	response.OK(c, result)
}

// SuggestUsers GET /api/v1/users/suggest — 所有登录用户可查的轻量用户列表（支持搜索）
func SuggestUsers(c *gin.Context) {
	q := c.Query("q")
	// 直接从 DB 查 active 用户，支持模糊匹配 name/email
	users, _, err := repository.NewUserRepository().List(1, 100, q, "")
	if err != nil {
		response.ServerError(c, err)
		return
	}
	// 简化输出：只给 id/name/email/role
	out := make([]map[string]any, 0, len(users))
	for _, u := range users {
		out = append(out, map[string]any{
			"id": u.ID.String(),
			"name": u.Name,
			"email": u.Email,
			"role_name": func() string {
				if u.Role != nil {
					return u.Role.Name
				}
				if u.RoleName != "" {
					return u.RoleName
				}
				return ""
			}(),
		})
	}
	response.OK(c, out)
}

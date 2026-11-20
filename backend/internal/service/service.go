// Package service 提供业务逻辑层
package service

import (
	"errors"
	"fmt"
	"strings"
	"time"

	"meeting-platform/config"
	"meeting-platform/internal/model"
	"meeting-platform/internal/repository"
	jwtutil "meeting-platform/pkg/jwt"
	"meeting-platform/pkg/storage"
	"meeting-platform/pkg/utils"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
)

// AuthService 鉴权业务
type AuthService struct {
	userRepo *repository.UserRepository
	cfg      *config.Config
	signer   *jwtutil.Signer
}

// NewAuthService 创建 AuthService
func NewAuthService(userRepo *repository.UserRepository, cfg *config.Config, signer *jwtutil.Signer) *AuthService {
	return &AuthService{userRepo: userRepo, cfg: cfg, signer: signer}
}

// RegisterRequest 注册请求
type RegisterRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
	Name     string `json:"name" binding:"required,min=1,max=100"`
	Role     string `json:"role"` // admin / teacher / student，默认 student
}

// LoginRequest 登录请求
type LoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

// TokenPair 登录成功返回的 Token 对
type TokenPair struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"` // 秒
	TokenType    string `json:"token_type"`
}

// Register 用户注册
func (s *AuthService) Register(req *RegisterRequest) (*model.User, error) {
	// 检查邮箱是否已存在
	if _, err := s.userRepo.FindByEmail(req.Email); err == nil {
		return nil, errors.New("email already registered")
	}

	// 查找/设置角色
	roleName := req.Role
	if roleName == "" {
		roleName = "student"
	}
	role, err := s.userRepo.RoleByName(roleName)
	if err != nil {
		return nil, fmt.Errorf("role not found: %s", roleName)
	}

	// 加密密码
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, err
	}

	user := &model.User{
		Email:        req.Email,
		PasswordHash: string(hash),
		Name:         req.Name,
		RoleID:       role.ID,
		Status:       "active",
	}
	if err := s.userRepo.Create(user); err != nil {
		return nil, err
	}
	// 预填充 role 信息以便前端直接使用
	user.Role = role
	user.RoleName = role.Name
	return user, nil
}

// Login 用户登录，返回 Token 对
func (s *AuthService) Login(req *LoginRequest) (*TokenPair, *model.User, error) {
	user, err := s.userRepo.FindByEmail(req.Email)
	if err != nil {
		return nil, nil, errors.New("invalid email or password")
	}
	if user.Status != "active" {
		return nil, nil, errors.New("account disabled")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		return nil, nil, errors.New("invalid email or password")
	}

	accessToken, err := s.signer.IssueAccessToken(user.ID.String(), user.Email, user.Name, user.Role.Name)
	if err != nil {
		return nil, nil, err
	}
	refreshToken, err := s.signer.IssueRefreshToken(user.ID.String())
	if err != nil {
		return nil, nil, err
	}

	user.RoleName = user.Role.Name
	return &TokenPair{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    s.cfg.JWT.ExpireHours * 3600,
		TokenType:    "Bearer",
	}, user, nil
}

// Refresh 使用 Refresh Token 换发新的 Access Token
func (s *AuthService) Refresh(refreshToken string) (*TokenPair, error) {
	userID, err := s.signer.ParseRefresh(refreshToken)
	if err != nil {
		return nil, errors.New("invalid refresh token")
	}
	user, err := s.userRepo.FindByID(userID)
	if err != nil {
		return nil, errors.New("user not found")
	}
	accessToken, err := s.signer.IssueAccessToken(user.ID.String(), user.Email, user.Name, user.Role.Name)
	if err != nil {
		return nil, err
	}
	return &TokenPair{
		AccessToken:  accessToken,
		ExpiresIn:    s.cfg.JWT.ExpireHours * 3600,
		TokenType:    "Bearer",
	}, nil
}

// ============================================================
// MeetingService 会议业务
// ============================================================

// MeetingService 会议业务层
type MeetingService struct {
	meetingRepo *repository.MeetingRepository
	userRepo    *repository.UserRepository
	recRepo     *repository.RecordingRepository
	matRepo     *repository.MaterialRepository
	storage     *storage.Service
	notifier    *NotificationService
}

// NewMeetingService 创建 MeetingService
func NewMeetingService(
	meetingRepo *repository.MeetingRepository,
	userRepo *repository.UserRepository,
	recRepo *repository.RecordingRepository,
	matRepo *repository.MaterialRepository,
	st *storage.Service,
	notifier *NotificationService,
) *MeetingService {
	return &MeetingService{
		meetingRepo: meetingRepo,
		userRepo:    userRepo,
		recRepo:     recRepo,
		matRepo:     matRepo,
		storage:     st,
		notifier:    notifier,
	}
}

// CreateMeetingRequest 创建会议请求
type CreateMeetingRequest struct {
	Title         string   `json:"title" binding:"required,min=1,max=200"`
	Description   string   `json:"description"`
	StartTime     string   `json:"start_time" binding:"required"` // RFC3339
	EndTime       *string  `json:"end_time"`
	MeetingType   string   `json:"meeting_type"` // tutoring / group_class / webinar
	ParticipantIDs []string `json:"participant_ids"` // 要邀请的用户 UUID 列表
	Settings      string   `json:"settings"` // JSONB
}

// CreateMeeting 创建会议
func (s *MeetingService) CreateMeeting(organizerID string, req *CreateMeetingRequest) (*model.Meeting, error) {
	// 解析时间
	startTime, err := time.Parse(time.RFC3339, req.StartTime)
	if err != nil {
		return nil, fmt.Errorf("invalid start_time: %w", err)
	}
	var endTimePtr *time.Time
	if req.EndTime != nil && *req.EndTime != "" {
		t, err := time.Parse(time.RFC3339, *req.EndTime)
		if err != nil {
			return nil, fmt.Errorf("invalid end_time: %w", err)
		}
		endTimePtr = &t
	}

	meetingType := model.MeetingType(req.MeetingType)
	if meetingType == "" {
		meetingType = model.TypeTutoring
	}

	settings := req.Settings
	if settings == "" {
		settings = `{"auto_record":false,"allow_screen_share":true,"allow_annotation":true}`
	}

	// 生成唯一房间名
	roomName := utils.RandomRoomName()
	// 重试避免冲突
	for i := 0; i < 3; i++ {
		if _, err := s.meetingRepo.FindByRoomName(roomName); err != nil {
			break
		}
		roomName = utils.RandomRoomName()
	}

	meeting := &model.Meeting{
		Title:       req.Title,
		Description: req.Description,
		OrganizerID: uuid.MustParse(organizerID),
		StartTime:   startTime,
		EndTime:     endTimePtr,
		Status:      model.StatusScheduled,
		MeetingType: meetingType,
		RoomName:    roomName,
		Settings:    settings,
	}
	if err := s.meetingRepo.Create(meeting); err != nil {
		return nil, err
	}

	// 组织者自动作为 host 加入
	host := &model.MeetingParticipant{
		MeetingID:       meeting.ID,
		UserID:          uuid.MustParse(organizerID),
		ParticipantRole: model.PartRoleHost,
		Status:          model.PartConfirmed,
	}
	if err := s.meetingRepo.AddParticipant(host); err != nil {
		return nil, err
	}

	// 批量邀请其他参会者
	if len(req.ParticipantIDs) > 0 {
		participants := make([]*model.MeetingParticipant, 0, len(req.ParticipantIDs))
		for _, pid := range req.ParticipantIDs {
			if pid == organizerID {
				continue
			}
			participants = append(participants, &model.MeetingParticipant{
				MeetingID:       meeting.ID,
				UserID:          uuid.MustParse(pid),
				ParticipantRole: model.PartRoleAttendee,
				Status:          model.PartInvited,
			})
		}
		if len(participants) > 0 {
			if err := s.meetingRepo.AddParticipants(participants); err != nil {
				return nil, err
			}
		}
	}

	// 返回完整信息
	full, _ := s.meetingRepo.FindByID(meeting.ID.String())

	// 异步发送会议邀请邮件（不阻塞创建响应；SMTP 未配置时仅打印日志）
	if s.notifier != nil {
		go s.notifier.NotifyMeetingCreated(meeting.ID.String())
	}

	return full, nil
}

// ListMeetings 获取用户可见会议列表
func (s *MeetingService) ListMeetings(userID string, page, pageSize int, status string) ([]model.Meeting, int64, error) {
	return s.meetingRepo.ListByUser(userID, page, pageSize, status)
}

// GetMeeting 获取会议详情（含权限校验）
func (s *MeetingService) GetMeeting(userID, meetingID string) (*model.Meeting, error) {
	isPart, err := s.meetingRepo.IsParticipant(meetingID, userID)
	if err != nil {
		return nil, err
	}
	if !isPart {
		return nil, errors.New("forbidden: not a meeting participant")
	}
	return s.meetingRepo.FindByID(meetingID)
}

// CancelMeeting 取消会议（仅组织者）
func (s *MeetingService) CancelMeeting(userID, meetingID string) error {
	meeting, err := s.meetingRepo.FindByID(meetingID)
	if err != nil {
		return errors.New("meeting not found")
	}
	if meeting.OrganizerID.String() != userID {
		return errors.New("forbidden: only organizer can cancel")
	}
	if meeting.Status == model.StatusCompleted || meeting.Status == model.StatusCancelled {
		return errors.New("meeting already ended")
	}
	return s.meetingRepo.UpdateStatus(meetingID, model.StatusCancelled)
}

// JoinMeeting 用户标记加入会议（同时生成 LiveKit Token）
func (s *MeetingService) JoinMeeting(userID, meetingID string) error {
	meeting, err := s.meetingRepo.FindByID(meetingID)
	if err != nil {
		return errors.New("meeting not found")
	}
	if meeting.Status != model.StatusScheduled && meeting.Status != model.StatusInProgress {
		return errors.New("meeting not joinable")
	}
	if meeting.Status == model.StatusScheduled {
		_ = s.meetingRepo.UpdateStatus(meetingID, model.StatusInProgress)
	}
	_ = time.Now() // 预留：可用于更新 participant 的 joined_at 字段
	return s.meetingRepo.SetParticipantStatus(meetingID, userID, model.PartJoined)
}

// InviteParticipants 组织者邀请参会者加入会议（幂等：已在会中的跳过）
func (s *MeetingService) InviteParticipants(organizerID, meetingID string, userIDs []string) (int, error) {
	meeting, err := s.meetingRepo.FindByID(meetingID)
	if err != nil {
		return 0, errors.New("meeting not found")
	}
	if meeting.OrganizerID.String() != organizerID {
		return 0, errors.New("forbidden: only organizer can invite")
	}

	added := 0
	for _, pid := range userIDs {
		if pid == organizerID {
			continue
		}
		isPart, _ := s.meetingRepo.IsParticipant(meetingID, pid)
		if isPart {
			continue
		}
		// 校验用户存在且 active
		u, err := s.userRepo.FindByID(pid)
		if err != nil || u.Status != "active" {
			continue
		}
		p := &model.MeetingParticipant{
			MeetingID:       meeting.ID,
			UserID:          uuid.MustParse(pid),
			ParticipantRole: model.PartRoleAttendee,
			Status:          model.PartInvited,
		}
		if err := s.meetingRepo.AddParticipant(p); err != nil {
			continue
		}
		added++
	}
	return added, nil
}

// hasEnded 判断会议是否已结束（已结束/已取消，或已过结束时间）
func hasEnded(m *model.Meeting) bool {
	if m.Status == model.StatusCompleted || m.Status == model.StatusCancelled {
		return true
	}
	return m.EndTime != nil && m.EndTime.Before(time.Now())
}

// PurgeMeeting 彻底删除已结束的会议：同时清理录制视频、会议材料及磁盘文件
// 权限：组织者或管理员
func (s *MeetingService) PurgeMeeting(userID, userRole, meetingID string) (*PurgeResult, error) {
	meeting, err := s.meetingRepo.FindByID(meetingID)
	if err != nil {
		return nil, errors.New("meeting not found")
	}
	if meeting.OrganizerID.String() != userID && userRole != "admin" {
		return nil, errors.New("forbidden: only organizer or admin can delete meeting")
	}
	if !hasEnded(meeting) {
		return nil, errors.New("meeting not ended yet, cannot delete")
	}

	// 1. 先清理磁盘文件（录制 + 材料）
	recordings, _ := s.recRepo.ListByMeeting(meetingID)
	materials, _ := s.matRepo.ListByMeeting(meetingID)
	for _, r := range recordings {
		if rel := storageRelPath(r.FileURL); rel != "" {
			_ = s.storage.Delete(rel)
		}
	}
	for _, m := range materials {
		if rel := storageRelPath(m.FileURL); rel != "" {
			_ = s.storage.Delete(rel)
		}
	}

	// 2. 再删除数据库记录（事务内级联硬删除）
	if err := s.meetingRepo.PurgeCascade(meetingID); err != nil {
		return nil, err
	}

	return &PurgeResult{
		Recordings: len(recordings),
		Materials:  len(materials),
	}, nil
}

// PurgeResult 彻底删除会议的清理统计
type PurgeResult struct {
	Recordings int `json:"deleted_recordings"`
	Materials  int `json:"deleted_materials"`
}

// storageRelPath 将 "/storage/xxx/yyy" 形式的文件 URL 转换为存储根下的相对路径
func storageRelPath(fileURL string) string {
	return strings.TrimPrefix(fileURL, "/storage/")
}

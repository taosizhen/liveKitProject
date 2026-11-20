// Package service 提供业务逻辑层
package service

import (
	"fmt"
	"mime/multipart"
	"path/filepath"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"

	"meeting-platform/config"
	"meeting-platform/internal/model"
	"meeting-platform/internal/repository"
	"meeting-platform/pkg/storage"

	"github.com/google/uuid"
)

// bcryptHash 工具函数：加密密码
func bcryptHash(p []byte) (string, error) {
	b, err := bcrypt.GenerateFromPassword(p, bcrypt.DefaultCost)
	return string(b), err
}

// ============================================================
// RecordingService —— 会议录制（客户端录制文件上传）
// ============================================================

// RecordingService 录制业务
type RecordingService struct {
	repo   *repository.RecordingRepository
	meetingRepo *repository.MeetingRepository
	userRepo    *repository.UserRepository
	storage     *storage.Service
}

// NewRecordingService 创建 RecordingService
func NewRecordingService(
	repo *repository.RecordingRepository,
	meetingRepo *repository.MeetingRepository,
	userRepo *repository.UserRepository,
	st *storage.Service,
) *RecordingService {
	return &RecordingService{repo: repo, meetingRepo: meetingRepo, userRepo: userRepo, storage: st}
}

// RegisterRecordingRequest 客户端上报录制信息（上传后的元数据）
type RegisterRecordingRequest struct {
	MeetingID    string `json:"meeting_id" binding:"required"`
	FileRelative string `json:"file_relative" binding:"required"` // Storage 内部相对路径
	DurationSec  int    `json:"duration_sec"`
}

// RegisterRecording 注册一条录制记录（由客户端 MediaRecorder 上传文件后调用）
func (s *RecordingService) RegisterRecording(userID string, req *RegisterRecordingRequest) (*model.Recording, error) {
	// 1. 校验用户是会议参与者
	isPart, err := s.meetingRepo.IsParticipant(req.MeetingID, userID)
	if err != nil {
		return nil, err
	}
	if !isPart {
		return nil, fmt.Errorf("forbidden: not a meeting participant")
	}

	// 2. 校验文件真实存在于存储目录
	fullPath := s.storage.FullPath(req.FileRelative)
	if _, err := filepath.Abs(fullPath); err != nil {
		return nil, fmt.Errorf("invalid file path")
	}
	if fullPath != filepath.Clean(fullPath) {
		return nil, fmt.Errorf("invalid file path")
	}
	size, err := s.storage.Stat(req.FileRelative)
	if err != nil {
		return nil, fmt.Errorf("file not found in storage")
	}

	now := time.Now()
	rec := &model.Recording{
		MeetingID:     uuid.MustParse(req.MeetingID),
		FileURL:       "/storage/" + req.FileRelative, // 静态访问 URL
		DurationSec:   req.DurationSec,
		FileSizeBytes: size,
		Status:        model.RecCompleted,
		StartedAt:     &now,
		EndedAt:       &now,
	}
	if err := s.repo.Create(rec); err != nil {
		return nil, err
	}
	return rec, nil
}

// UploadRecording 保存客户端上传的录制文件（浏览器 MediaRecorder 生成的 webm）并创建录制记录
func (s *RecordingService) UploadRecording(
	userID, meetingID string,
	header *multipart.FileHeader,
	durationSec int,
) (*model.Recording, error) {
	// 1. 仅会议参与者可上传
	isPart, err := s.meetingRepo.IsParticipant(meetingID, userID)
	if err != nil {
		return nil, err
	}
	if !isPart {
		return nil, fmt.Errorf("forbidden: not a meeting participant")
	}

	// 2. 校验扩展名
	ext := strings.ToLower(filepath.Ext(header.Filename))
	if !storage.AllowTypes["recordings"][ext] {
		return nil, fmt.Errorf("unsupported recording type: %s", ext)
	}

	// 3. 落盘到 storage/recordings/YYYY-MM-DD/
	rel, size, err := s.storage.Save("recordings", header)
	if err != nil {
		return nil, err
	}

	// 4. 写入录制记录
	now := time.Now()
	rec := &model.Recording{
		MeetingID:     uuid.MustParse(meetingID),
		FileURL:       "/storage/" + rel,
		DurationSec:   durationSec,
		FileSizeBytes: size,
		Status:        model.RecCompleted,
		StartedAt:     &now,
		EndedAt:       &now,
	}
	if err := s.repo.Create(rec); err != nil {
		return nil, err
	}
	return rec, nil
}

// CompleteRecording 标记录制完成（带 LiveKit recording_id）
func (s *RecordingService) CompleteRecording(id, recordingID string, durationSec int) error {
	updates := map[string]interface{}{
		"status":      model.RecCompleted,
		"ended_at":    time.Now(),
		"duration_sec": durationSec,
	}
	if recordingID != "" {
		updates["livekit_recording_id"] = recordingID
	}
	return s.repo.Update(id, updates)
}

// DeleteRecording 删除录制（同时清理文件）
func (s *RecordingService) DeleteRecording(userID, recordingID string) error {
	rec, err := s.repo.FindByID(recordingID)
	if err != nil {
		return fmt.Errorf("recording not found")
	}
	meeting, err := s.meetingRepo.FindByID(rec.MeetingID.String())
	if err != nil {
		return err
	}
	// 仅组织者可删
	if meeting.OrganizerID.String() != userID {
		return fmt.Errorf("forbidden: only organizer can delete recording")
	}
	_ = s.storage.Delete(strings.TrimPrefix(rec.FileURL, "/storage/"))
	return s.repo.Delete(recordingID)
}

// ListByMeeting 会议录制列表
func (s *RecordingService) ListByMeeting(userID, meetingID string) ([]model.Recording, error) {
	isPart, _ := s.meetingRepo.IsParticipant(meetingID, userID)
	if !isPart {
		return nil, fmt.Errorf("forbidden")
	}
	return s.repo.ListByMeeting(meetingID)
}

// ============================================================
// MaterialService —— 会议材料上传/下载/删除
// ============================================================

// MaterialService 材料业务
type MaterialService struct {
	repo        *repository.MaterialRepository
	meetingRepo *repository.MeetingRepository
	userRepo    *repository.UserRepository
	storage     *storage.Service
}

// NewMaterialService 创建 MaterialService
func NewMaterialService(
	repo *repository.MaterialRepository,
	meetingRepo *repository.MeetingRepository,
	userRepo *repository.UserRepository,
	st *storage.Service,
) *MaterialService {
	return &MaterialService{repo: repo, meetingRepo: meetingRepo, userRepo: userRepo, storage: st}
}

// SaveAndCreate 将上传文件保存到存储并写入数据库
func (s *MaterialService) SaveAndCreate(userID, meetingID string, header *multipart.FileHeader) (*model.Material, error) {
	// 校验参与者
	isPart, err := s.meetingRepo.IsParticipant(meetingID, userID)
	if err != nil {
		return nil, err
	}
	if !isPart {
		return nil, fmt.Errorf("forbidden: not a meeting participant")
	}

	// 校验扩展名（materials 白名单）
	ext := strings.ToLower(filepath.Ext(header.Filename))
	if !storage.AllowTypes["materials"][ext] {
		return nil, fmt.Errorf("file type not allowed: %s", ext)
	}

	// 存储
	relPath, size, err := s.storage.Save("materials", header)
	if err != nil {
		return nil, fmt.Errorf("save file: %w", err)
	}

	material := &model.Material{
		MeetingID:  uuid.MustParse(meetingID),
		UploaderID: uuid.MustParse(userID),
		FileName:   header.Filename,
		FileURL:    "/storage/" + relPath,
		FileType:   strings.TrimPrefix(ext, "."),
		FileSize:   size,
	}
	if err := s.repo.Create(material); err != nil {
		// DB 失败，清理文件
		_ = s.storage.Delete(relPath)
		return nil, err
	}
	return material, nil
}

// ListByMeeting 会议材料列表
func (s *MaterialService) ListByMeeting(userID, meetingID string) ([]model.Material, error) {
	isPart, _ := s.meetingRepo.IsParticipant(meetingID, userID)
	if !isPart {
		return nil, fmt.Errorf("forbidden")
	}
	return s.repo.ListByMeeting(meetingID)
}

// Delete 删除材料（同时清理文件）
func (s *MaterialService) Delete(userID, materialID string) error {
	m, err := s.repo.FindByID(materialID)
	if err != nil {
		return fmt.Errorf("material not found")
	}
	// 组织者或上传者可删
	meeting, _ := s.meetingRepo.FindByID(m.MeetingID.String())
	if m.UploaderID.String() != userID && meeting.OrganizerID.String() != userID {
		return fmt.Errorf("forbidden")
	}
	_ = s.storage.Delete(strings.TrimPrefix(m.FileURL, "/storage/"))
	return s.repo.Delete(materialID)
}

// FullPath 获取材料磁盘路径
func (s *MaterialService) FullPath(relPath string) string {
	return s.storage.FullPath(strings.TrimPrefix(relPath, "/storage/"))
}

// ============================================================
// ChatService —— 聊天消息持久化（WebSocket 实时发送由 Hub 完成）
// ============================================================

// ChatService 聊天消息持久化业务
type ChatService struct {
	repo        *repository.ChatRepository
	meetingRepo *repository.MeetingRepository
}

// NewChatService 创建 ChatService
func NewChatService(repo *repository.ChatRepository, meetingRepo *repository.MeetingRepository) *ChatService {
	return &ChatService{repo: repo, meetingRepo: meetingRepo}
}

// Save 持久化一条聊天消息
func (s *ChatService) Save(meetingID, userID, content string) (*model.ChatMessage, error) {
	isPart, err := s.meetingRepo.IsParticipant(meetingID, userID)
	if err != nil {
		return nil, err
	}
	if !isPart {
		return nil, fmt.Errorf("forbidden")
	}
	msg := &model.ChatMessage{
		MeetingID: uuid.MustParse(meetingID),
		UserID:    uuid.MustParse(userID),
		Content:   content,
	}
	if err := s.repo.Save(msg); err != nil {
		return nil, err
	}
	return msg, nil
}

// History 拉取历史消息
func (s *ChatService) History(userID, meetingID string, limit int) ([]model.ChatMessage, error) {
	isPart, _ := s.meetingRepo.IsParticipant(meetingID, userID)
	if !isPart {
		return nil, fmt.Errorf("forbidden")
	}
	return s.repo.ListHistory(meetingID, limit)
}

// ============================================================
// UserAdminService —— 管理员用户管理
// ============================================================

// UserAdminService 管理员用户管理
type UserAdminService struct {
	userRepo *repository.UserRepository
	cfg      *config.Config
}

// NewUserAdminService 创建 UserAdminService
func NewUserAdminService(userRepo *repository.UserRepository, cfg *config.Config) *UserAdminService {
	return &UserAdminService{userRepo: userRepo, cfg: cfg}
}

// UpdateAvatarURL 更新指定用户的头像访问路径（写入 user.avatar_url）
func (s *UserAdminService) UpdateAvatarURL(userID, avatarURL string) error {
	return s.userRepo.Update(userID, map[string]interface{}{"avatar_url": avatarURL})
}

// CreateUserRequest 管理员创建用户
type CreateUserRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Name     string `json:"name" binding:"required,min=1,max=100"`
	Password string `json:"password" binding:"required,min=6"`
	Role     string `json:"role"` // admin / teacher / student，默认 student
}

// CreateUser 管理员创建账号
func (s *UserAdminService) CreateUser(req *CreateUserRequest) (*model.User, error) {
	if _, err := s.userRepo.FindByEmail(req.Email); err == nil {
		return nil, fmt.Errorf("email already exists")
	}
	roleName := req.Role
	if roleName == "" {
		roleName = "student"
	}
	role, err := s.userRepo.RoleByName(roleName)
	if err != nil {
		return nil, fmt.Errorf("role not found: %s", roleName)
	}
	hash, err := bcryptHash([]byte(req.Password))
	if err != nil {
		return nil, err
	}
	u := &model.User{
		Email:        req.Email,
		Name:         req.Name,
		PasswordHash: hash,
		RoleID:       role.ID,
		Status:       "active",
	}
	if err := s.userRepo.Create(u); err != nil {
		return nil, err
	}
	u.RoleName = role.Name
	return u, nil
}

// UpdateRoleOrStatus 更新用户角色或状态（管理员）
func (s *UserAdminService) UpdateRoleOrStatus(userID string, role string, status string) error {
	updates := map[string]interface{}{}
	if role != "" {
		r, err := s.userRepo.RoleByName(role)
		if err != nil {
			return fmt.Errorf("role not found")
		}
		updates["role_id"] = r.ID
	}
	if status != "" {
		updates["status"] = status
	}
	if len(updates) == 0 {
		return fmt.Errorf("no fields to update")
	}
	return s.userRepo.Update(userID, updates)
}

// DeleteUser 软删除用户（标记 disabled）
func (s *UserAdminService) DeleteUser(userID string) error {
	return s.userRepo.Update(userID, map[string]interface{}{"status": "disabled"})
}

// ListUsers 用户列表（管理员）
func (s *UserAdminService) ListUsers(page, pageSize int, search, role string) ([]model.User, int64, error) {
	return s.userRepo.List(page, pageSize, search, role)
}

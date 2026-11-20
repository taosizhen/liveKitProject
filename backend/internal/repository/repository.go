// Package repository 提供数据访问层
package repository

import (
	"time"

	"meeting-platform/internal/database"
	"meeting-platform/internal/model"

	"gorm.io/gorm"
)

// UserRepository 用户数据访问
type UserRepository struct {
	db *gorm.DB
}

// NewUserRepository 创建 UserRepository
func NewUserRepository() *UserRepository {
	return &UserRepository{db: database.DB}
}

// Create 新建用户
func (r *UserRepository) Create(user *model.User) error {
	return r.db.Create(user).Error
}

// FindByEmail 按邮箱查找
func (r *UserRepository) FindByEmail(email string) (*model.User, error) {
	var u model.User
	err := r.db.Preload("Role").Where("email = ?", email).First(&u).Error
	return &u, err
}

// FindByID 按 ID 查找
func (r *UserRepository) FindByID(id string) (*model.User, error) {
	var u model.User
	err := r.db.Preload("Role").Where("id = ?", id).First(&u).Error
	return &u, err
}

// List 分页列表，支持搜索和角色过滤
func (r *UserRepository) List(page, pageSize int, search string, role string) ([]model.User, int64, error) {
	var users []model.User
	var total int64

	q := r.db.Model(&model.User{})
	if search != "" {
		q = q.Where("name ILIKE ? OR email ILIKE ?", "%"+search+"%", "%"+search+"%")
	}
	if role != "" {
		q = q.Joins("JOIN roles ON roles.id = users.role_id").Where("roles.name = ?", role)
	}

	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * pageSize
	if err := q.Preload("Role").Order("created_at DESC").Offset(offset).Limit(pageSize).Find(&users).Error; err != nil {
		return nil, 0, err
	}
	return users, total, nil
}

// Update 更新用户
func (r *UserRepository) Update(id string, updates map[string]interface{}) error {
	return r.db.Model(&model.User{}).Where("id = ?", id).Updates(updates).Error
}

// RoleByName 按名称查角色
func (r *UserRepository) RoleByName(name string) (*model.Role, error) {
	var role model.Role
	err := r.db.Where("name = ?", name).First(&role).Error
	return &role, err
}

// MeetingRepository 会议数据访问
type MeetingRepository struct {
	db *gorm.DB
}

// NewMeetingRepository 创建 MeetingRepository
func NewMeetingRepository() *MeetingRepository {
	return &MeetingRepository{db: database.DB}
}

// Create 新建会议
func (r *MeetingRepository) Create(m *model.Meeting) error {
	return r.db.Create(m).Error
}

// FindByID 按 ID 查会议（带组织者和参与者）
func (r *MeetingRepository) FindByID(id string) (*model.Meeting, error) {
	var m model.Meeting
	err := r.db.
		Preload("Organizer").
		Preload("Participants.User").
		Where("id = ?", id).First(&m).Error
	return &m, err
}

// FindByRoomName 按 RoomName 查会议
func (r *MeetingRepository) FindByRoomName(roomName string) (*model.Meeting, error) {
	var m model.Meeting
	err := r.db.Where("room_name = ?", roomName).First(&m).Error
	return &m, err
}

// ListByUser 查用户可见的会议（创建者 或 参会者）
func (r *MeetingRepository) ListByUser(userID string, page, pageSize int, status string) ([]model.Meeting, int64, error) {
	var meetings []model.Meeting
	var total int64

	q := r.db.Model(&model.Meeting{}).
		Where("organizer_id = ? OR id IN (SELECT meeting_id FROM meeting_participants WHERE user_id = ?)", userID, userID)
	if status != "" {
		q = q.Where("status = ?", status)
	}

	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * pageSize
	if err := q.Preload("Organizer").
		Order("start_time DESC").
		Offset(offset).Limit(pageSize).
		Find(&meetings).Error; err != nil {
		return nil, 0, err
	}
	return meetings, total, nil
}

// Update 更新会议
func (r *MeetingRepository) Update(id string, updates map[string]interface{}) error {
	return r.db.Model(&model.Meeting{}).Where("id = ?", id).Updates(updates).Error
}

// UpdateStatus 更新会议状态
func (r *MeetingRepository) UpdateStatus(id string, status model.MeetingStatus) error {
	return r.db.Model(&model.Meeting{}).Where("id = ?", id).Update("status", status).Error
}

// AddParticipant 新增参会人员
func (r *MeetingRepository) AddParticipant(p *model.MeetingParticipant) error {
	return r.db.Create(p).Error
}

// AddParticipants 批量新增参会人员
func (r *MeetingRepository) AddParticipants(participants []*model.MeetingParticipant) error {
	return r.db.Create(participants).Error
}

// IsParticipant 检查用户是否为会议参与者
func (r *MeetingRepository) IsParticipant(meetingID, userID string) (bool, error) {
	var count int64
	err := r.db.Model(&model.MeetingParticipant{}).
		Where("meeting_id = ? AND user_id = ?", meetingID, userID).
		Count(&count).Error
	if err != nil {
		return false, err
	}
	return count > 0, nil
}

// SetParticipantStatus 更新参会者状态
func (r *MeetingRepository) SetParticipantStatus(meetingID, userID string, status model.ParticipantStatus) error {
	return r.db.Model(&model.MeetingParticipant{}).
		Where("meeting_id = ? AND user_id = ?", meetingID, userID).
		Update("status", status).Error
}

// PurgeCascade 彻底删除会议及其所有关联数据（硬删除，不做软删除）
// 关联表：参会人员、聊天消息、录制、材料
func (r *MeetingRepository) PurgeCascade(meetingID string) error {
	return r.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Unscoped().Where("meeting_id = ?", meetingID).Delete(&model.ChatMessage{}).Error; err != nil {
			return err
		}
		if err := tx.Unscoped().Where("meeting_id = ?", meetingID).Delete(&model.Recording{}).Error; err != nil {
			return err
		}
		if err := tx.Unscoped().Where("meeting_id = ?", meetingID).Delete(&model.Material{}).Error; err != nil {
			return err
		}
		if err := tx.Unscoped().Where("meeting_id = ?", meetingID).Delete(&model.MeetingParticipant{}).Error; err != nil {
			return err
		}
		return tx.Unscoped().Where("id = ?", meetingID).Delete(&model.Meeting{}).Error
	})
}

// MarkNotified 标记「会议创建通知」已发送
func (r *MeetingRepository) MarkNotified(id string, t time.Time) error {
	return r.db.Model(&model.Meeting{}).Where("id = ?", id).Update("notified_at", t).Error
}

// MarkReminderSent 标记「会前 8 小时提醒」已处理
func (r *MeetingRepository) MarkReminderSent(id string, t time.Time) error {
	return r.db.Model(&model.Meeting{}).Where("id = ?", id).Update("reminder_sent_at", t).Error
}

// ListDueReminders 查询需要发送会前提醒的会议：
// 待开始、已发过创建通知、未发过提醒
// 注意：不同数据库驱动存储时间的时区偏移不一致（UTC / +08:00），
// 字符串比较不可靠，因此时间窗口在 Go 侧过滤
func (r *MeetingRepository) ListDueReminders(now time.Time) ([]model.Meeting, error) {
	var list []model.Meeting
	err := r.db.
		Preload("Organizer").
		Preload("Participants.User").
		Where("status = ?", model.StatusScheduled).
		Where("notified_at IS NOT NULL").
		Where("reminder_sent_at IS NULL").
		Find(&list).Error
	if err != nil {
		return nil, err
	}

	deadline := now.Add(8 * time.Hour)
	due := make([]model.Meeting, 0, len(list))
	for _, m := range list {
		if m.StartTime.After(now) && !m.StartTime.After(deadline) {
			due = append(due, m)
		}
	}
	return due, nil
}

// ============================================================
// RecordingRepository / MaterialRepository / ChatRepository
// ============================================================

// RecordingRepository 录制文件数据访问
type RecordingRepository struct{ db *gorm.DB }

// NewRecordingRepository 创建
func NewRecordingRepository() *RecordingRepository { return &RecordingRepository{db: database.DB} }

// Create 新建录制记录
func (r *RecordingRepository) Create(rec *model.Recording) error { return r.db.Create(rec).Error }

// ListByMeeting 会议的录制列表
func (r *RecordingRepository) ListByMeeting(meetingID string) ([]model.Recording, error) {
	var list []model.Recording
	err := r.db.Where("meeting_id = ?", meetingID).Order("created_at DESC").Find(&list).Error
	return list, err
}

// Update 更新状态 / 文件信息
func (r *RecordingRepository) Update(id string, updates map[string]interface{}) error {
	return r.db.Model(&model.Recording{}).Where("id = ?", id).Updates(updates).Error
}

// Delete 删除录制记录
func (r *RecordingRepository) Delete(id string) error { return r.db.Where("id = ?", id).Delete(&model.Recording{}).Error }

// FindByID 按 ID 查
func (r *RecordingRepository) FindByID(id string) (*model.Recording, error) {
	var rec model.Recording
	err := r.db.Where("id = ?", id).First(&rec).Error
	return &rec, err
}

// MaterialRepository 会议材料数据访问
type MaterialRepository struct{ db *gorm.DB }

// NewMaterialRepository 创建
func NewMaterialRepository() *MaterialRepository { return &MaterialRepository{db: database.DB} }

// Create 新建材料
func (r *MaterialRepository) Create(m *model.Material) error { return r.db.Create(m).Error }

// ListByMeeting 会议材料列表
func (r *MaterialRepository) ListByMeeting(meetingID string) ([]model.Material, error) {
	var list []model.Material
	err := r.db.Where("meeting_id = ?", meetingID).Order("created_at DESC").Find(&list).Error
	return list, err
}

// Delete 删除
func (r *MaterialRepository) Delete(id string) error { return r.db.Where("id = ?", id).Delete(&model.Material{}).Error }

// FindByID 按 ID 查
func (r *MaterialRepository) FindByID(id string) (*model.Material, error) {
	var m model.Material
	err := r.db.Where("id = ?", id).First(&m).Error
	return &m, err
}

// ChatRepository 聊天消息数据访问
type ChatRepository struct{ db *gorm.DB }

// NewChatRepository 创建
func NewChatRepository() *ChatRepository { return &ChatRepository{db: database.DB} }

// Save 持久化一条消息
func (r *ChatRepository) Save(msg *model.ChatMessage) error { return r.db.Create(msg).Error }

// ListHistory 拉取历史消息（最近 N 条）
func (r *ChatRepository) ListHistory(meetingID string, limit int) ([]model.ChatMessage, error) {
	var list []model.ChatMessage
	if limit <= 0 {
		limit = 100
	}
	err := r.db.Preload("User").Where("meeting_id = ?", meetingID).Order("created_at DESC").Limit(limit).Find(&list).Error
	// 反转为升序（前端消费时间线）
	for i, j := 0, len(list)-1; i < j; i, j = i+1, j-1 {
		list[i], list[j] = list[j], list[i]
	}
	return list, err
}

// CountByMeeting 统计房间消息数
func (r *ChatRepository) CountByMeeting(meetingID string) (int64, error) {
	var n int64
	err := r.db.Model(&model.ChatMessage{}).Where("meeting_id = ?", meetingID).Count(&n).Error
	return n, err
}

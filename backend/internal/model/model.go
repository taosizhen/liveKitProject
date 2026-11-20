// Package model 定义 GORM 数据模型
package model

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// BaseModel 公共基础字段，所有表共享（UUID 由 BeforeCreate 钩子生成，兼容 sqlite/postgres）
type BaseModel struct {
	ID        uuid.UUID      `gorm:"type:varchar(36);primaryKey" json:"id"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

// BeforeCreate GORM 钩子：自动生成 UUID
func (b *BaseModel) BeforeCreate(tx *gorm.DB) error {
	if b.ID == uuid.Nil {
		b.ID = uuid.New()
	}
	return nil
}

// ============================================================
// 用户 & 权限
// ============================================================

// Role 角色：admin / teacher / student
type Role struct {
	BaseModel
	Name        string `gorm:"uniqueIndex;size:50;not null" json:"name"`
	Description string `gorm:"size:255" json:"description"`
	Permissions []Permission `gorm:"many2many:role_permissions;" json:"permissions,omitempty"`
}

// Permission 权限项
type Permission struct {
	BaseModel
	Name      string `gorm:"uniqueIndex;size:100;not null" json:"name"`
	Resource  string `gorm:"size:50" json:"resource"`
	Action    string `gorm:"size:50" json:"action"`
}

// RolePermission 角色-权限关联（显式定义以支持 GORM）
type RolePermission struct {
	RoleID       uuid.UUID `gorm:"type:uuid;primaryKey" json:"role_id"`
	PermissionID uuid.UUID `gorm:"type:uuid;primaryKey" json:"permission_id"`
}

// User 用户表
type User struct {
	BaseModel
	Email        string  `gorm:"uniqueIndex;size:255;not null" json:"email"`
	PasswordHash string  `gorm:"size:255;not null" json:"-"`
	Phone        *string `gorm:"size:20" json:"phone,omitempty"`
	Name         string  `gorm:"size:100;not null" json:"name"`
	AvatarURL    *string `gorm:"size:500" json:"avatar_url,omitempty"`
	RoleID       uuid.UUID `gorm:"type:uuid;index" json:"role_id"`
	Role         *Role   `gorm:"foreignKey:RoleID" json:"role,omitempty"`
	Status       string  `gorm:"size:20;default:active;index" json:"status"` // active / disabled

	// 辅助字段（非数据库列，由业务层填充）
	RoleName string `gorm:"-" json:"role_name,omitempty"`
}

// ============================================================
// 会议
// ============================================================

// MeetingStatus 会议状态枚举
type MeetingStatus string

const (
	StatusScheduled MeetingStatus = "scheduled"
	StatusInProgress MeetingStatus = "in_progress"
	StatusCompleted  MeetingStatus = "completed"
	StatusCancelled  MeetingStatus = "cancelled"
)

// MeetingType 会议类型枚举
type MeetingType string

const (
	TypeTutoring   MeetingType = "tutoring"
	TypeGroupClass MeetingType = "group_class"
	TypeWebinar    MeetingType = "webinar"
)

// Meeting 会议主表
type Meeting struct {
	BaseModel
	Title       string        `gorm:"size:200;not null" json:"title"`
	Description string        `gorm:"type:text" json:"description"`
	OrganizerID uuid.UUID     `gorm:"type:uuid;index;not null" json:"organizer_id"`
	Organizer   *User         `gorm:"foreignKey:OrganizerID" json:"organizer,omitempty"`
	StartTime   time.Time     `gorm:"index;not null" json:"start_time"`
	EndTime     *time.Time    `json:"end_time"`
	Status      MeetingStatus `gorm:"size:20;default:scheduled;index" json:"status"`
	MeetingType MeetingType   `gorm:"size:30;default:tutoring" json:"meeting_type"`
	RoomName    string        `gorm:"uniqueIndex;size:100;not null" json:"room_name"`
	// Settings JSONB 字段：录制开关、标注权限、是否允许屏幕共享等
	Settings string `gorm:"type:jsonb;default:'{}'" json:"settings"`

	// 邮件通知时间戳（用于发送去重：创建通知 / 会前 8 小时提醒）
	NotifiedAt     *time.Time `json:"notified_at,omitempty"`
	ReminderSentAt *time.Time `json:"reminder_sent_at,omitempty"`

	Participants []MeetingParticipant `gorm:"foreignKey:MeetingID" json:"participants,omitempty"`
	Recordings   []Recording           `gorm:"foreignKey:MeetingID" json:"recordings,omitempty"`
	Materials    []Material            `gorm:"foreignKey:MeetingID" json:"materials,omitempty"`
}

// ParticipantRole 参会者在会议中的角色
type ParticipantRole string

const (
	PartRoleHost    ParticipantRole = "host"
	PartRoleSpeaker ParticipantRole = "speaker"
	PartRoleAttendee ParticipantRole = "attendee"
)

// ParticipantStatus 参会状态
type ParticipantStatus string

const (
	PartInvited    ParticipantStatus = "invited"
	PartConfirmed  ParticipantStatus = "confirmed"
	PartJoined     ParticipantStatus = "joined"
	PartDeclined   ParticipantStatus = "declined"
)

// MeetingParticipant 会议参会人员关联
type MeetingParticipant struct {
	BaseModel
	MeetingID       uuid.UUID         `gorm:"type:uuid;index;not null" json:"meeting_id"`
	UserID          uuid.UUID         `gorm:"type:uuid;index;not null" json:"user_id"`
	User            *User             `gorm:"foreignKey:UserID" json:"user,omitempty"`
	ParticipantRole ParticipantRole   `gorm:"size:20;default:attendee" json:"participant_role"`
	Status          ParticipantStatus `gorm:"size:20;default:invited" json:"status"`
	JoinedAt        *time.Time        `json:"joined_at,omitempty"`
	LeftAt          *time.Time        `json:"left_at,omitempty"`
}

// ============================================================
// 录制
// ============================================================

// RecordingStatus 录制状态
type RecordingStatus string

const (
	RecRecording  RecordingStatus = "recording"
	RecProcessing RecordingStatus = "processing"
	RecCompleted  RecordingStatus = "completed"
	RecFailed     RecordingStatus = "failed"
)

// Recording 会议录制文件
type Recording struct {
	BaseModel
	MeetingID          uuid.UUID       `gorm:"type:uuid;index;not null" json:"meeting_id"`
	LiveKitRecordingID string          `gorm:"size:200;index" json:"livekit_recording_id"`
	FileURL            string          `gorm:"size:500" json:"file_url"`
	DurationSec        int             `json:"duration_sec"`
	FileSizeBytes      int64           `json:"file_size_bytes"`
	Status             RecordingStatus `gorm:"size:20;default:recording;index" json:"status"`
	StartedAt          *time.Time      `json:"started_at,omitempty"`
	EndedAt            *time.Time      `json:"ended_at,omitempty"`
}

// ============================================================
// 会议材料
// ============================================================

// Material 会议参考材料
type Material struct {
	BaseModel
	MeetingID uuid.UUID `gorm:"type:uuid;index;not null" json:"meeting_id"`
	UploaderID uuid.UUID `gorm:"type:uuid;index" json:"uploader_id"`
	FileName  string    `gorm:"size:255;not null" json:"file_name"`
	FileURL   string    `gorm:"size:500;not null" json:"file_url"`
	FileType  string    `gorm:"size:50" json:"file_type"`
	FileSize  int64     `json:"file_size"`
}

// ============================================================
// 聊天消息（实时）
// ============================================================

// ChatMessage 会议内聊天消息（持久化可选）
type ChatMessage struct {
	BaseModel
	MeetingID uuid.UUID `gorm:"type:uuid;index;not null" json:"meeting_id"`
	UserID    uuid.UUID `gorm:"type:uuid;index;not null" json:"user_id"`
	User      *User     `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Content   string    `gorm:"type:text;not null" json:"content"`
}

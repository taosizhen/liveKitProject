// Package livekitutil 提供 LiveKit Client 集成（Token 签发、录制触发）
package livekitutil

import (
	"encoding/json"
	"fmt"
	"time"

	"meeting-platform/config"

	"github.com/livekit/protocol/auth"
)

// Service LiveKit 集成服务
type Service struct {
	cfg *config.LiveKitConfig
}

// NewService 创建 LiveKit Service
func NewService(cfg *config.LiveKitConfig) *Service {
	return &Service{cfg: cfg}
}

// GenerateJoinToken 为指定用户签发进入指定房间的 LiveKit Token
// roomName: LiveKit Room 名
// userID:   平台用户 ID（也是 LiveKit participant identity）
// userName: 显示名
// role:     平台角色（admin/teacher/student），写入 metadata 供会议内动态主持人判定
// avatarURL: 头像访问路径，写入 metadata 供会议内席位/成员列表显示真实头像
// canPublish: 是否允许发布媒体流
// roomRecord: 是否允许录制房间（使用 LiveKit RoomRecord grant）
func (s *Service) GenerateJoinToken(roomName, userID, userName, role, avatarURL string, canPublish, roomRecord bool) (string, error) {
	if s.cfg.APIKey == "" || s.cfg.APISecret == "" {
		return "", fmt.Errorf("livekit credentials not configured")
	}

	validDuration := 24 * time.Hour

	grant := &auth.VideoGrant{
		RoomCreate: true,
		RoomJoin:   true,
		Room:       roomName,
		RoomRecord: roomRecord,
	}
	if canPublish {
		val := true
		grant.CanPublish = &val
	}

	// metadata 携带角色与头像，房间内各端据此做动态主持人判定与头像显示
	metadata, _ := json.Marshal(map[string]string{"role": role, "avatar_url": avatarURL})

	token := auth.NewAccessToken(s.cfg.APIKey, s.cfg.APISecret).
		SetIdentity(userID).
		SetName(userName).
		SetMetadata(string(metadata)).
		SetValidFor(validDuration).
		SetVideoGrant(grant)

	return token.ToJWT()
}

// GetParticipantPermission 根据平台角色返回 LiveKit 权限
func GetParticipantPermission(platformRole string) (canPublish bool, roomRecord bool) {
	switch platformRole {
	case "admin", "teacher":
		return true, true
	default:
		return true, false
	}
}

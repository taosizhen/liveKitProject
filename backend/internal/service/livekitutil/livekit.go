// Package livekitutil 提供 LiveKit Client 集成（Token 签发、录制触发）
package livekitutil

import (
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
// canPublish: 是否允许发布媒体流
// roomRecord: 是否允许录制房间（使用 LiveKit RoomRecord grant）
func (s *Service) GenerateJoinToken(roomName, userID, userName string, canPublish, roomRecord bool) (string, error) {
	if s.cfg.APIKey == "" || s.cfg.APISecret == "" {
		return "", fmt.Errorf("livekit credentials not configured")
	}

	now := time.Now()
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

	token := auth.NewAccessToken(s.cfg.APIKey, s.cfg.APISecret).
		SetIdentity(userID).
		SetName(userName).
		SetValidFor(validDuration).
		SetVideoGrant(grant)

	_ = now // 避免未使用

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

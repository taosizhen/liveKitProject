// Package utils 提供通用工具函数
package utils

import (
	"crypto/rand"
	"encoding/hex"
)

// RandomHex 生成指定字节数的随机十六进制字符串
func RandomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// RandomRoomName 生成 LiveKit 房间名，格式: meeting-xxxxxx
func RandomRoomName() string {
	return "meeting-" + RandomHex(6)
}

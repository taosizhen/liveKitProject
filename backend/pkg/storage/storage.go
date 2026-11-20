// Package storage 提供统一的本地文件存储服务（材料 / 录制 / 标注）
package storage

import (
	"fmt"
	"io"
	"mime/multipart"
	"os"
	"path/filepath"
	"strings"
	"time"

	"meeting-platform/config"
)

// Service 文件存储服务
type Service struct {
	dir          string
	maxSizeBytes int64
}

// NewService 创建存储服务，自动创建目录
func NewService(cfg config.StorageConfig) (*Service, error) {
	if err := os.MkdirAll(cfg.Dir, 0o755); err != nil {
		return nil, fmt.Errorf("create storage dir: %w", err)
	}
	return &Service{dir: cfg.Dir, maxSizeBytes: cfg.MaxSizeBytes}, nil
}

// Save 保存上传文件到指定子目录（materials / recordings / annotations）
// 返回：相对存储根的路径、文件大小、错误
func (s *Service) Save(subDir string, header *multipart.FileHeader) (string, int64, error) {
	if header.Size > s.maxSizeBytes {
		return "", 0, fmt.Errorf("file too large: %d > %d", header.Size, s.maxSizeBytes)
	}

	// 按日期创建子目录：YYYY-MM-DD
	dateDir := time.Now().Format("2006-01-02")
	targetDir := filepath.Join(s.dir, subDir, dateDir)
	if err := os.MkdirAll(targetDir, 0o755); err != nil {
		return "", 0, err
	}

	// 生成唯一文件名：<nanos>_<原文件名>（清理非法字符）
	safeName := cleanFileName(header.Filename)
	if safeName == "" {
		safeName = "file"
	}
	ext := filepath.Ext(safeName)
	name := fmt.Sprintf("%d_%s", time.Now().UnixNano(), safeName)
	_ = ext // 已并入 safeName

	fullPath := filepath.Join(targetDir, name)
	src, err := header.Open()
	if err != nil {
		return "", 0, err
	}
	defer src.Close()

	dst, err := os.Create(fullPath)
	if err != nil {
		return "", 0, err
	}
	defer dst.Close()

	if _, err := io.Copy(dst, src); err != nil {
		return "", 0, err
	}

	// 返回相对路径给前端（通过后端静态路由访问）
	rel, _ := filepath.Rel(s.dir, fullPath)
	rel = filepath.ToSlash(rel) // 统一正斜杠
	return rel, header.Size, nil
}

// SaveBytes 将字节切片保存到存储目录
func (s *Service) SaveBytes(subDir string, fileName string, data []byte) (string, int64, error) {
	dateDir := time.Now().Format("2006-01-02")
	targetDir := filepath.Join(s.dir, subDir, dateDir)
	if err := os.MkdirAll(targetDir, 0o755); err != nil {
		return "", 0, err
	}
	name := fmt.Sprintf("%d_%s", time.Now().UnixNano(), fileName)
	fullPath := filepath.Join(targetDir, name)
	if err := os.WriteFile(fullPath, data, 0o644); err != nil {
		return "", 0, err
	}
	rel, _ := filepath.Rel(s.dir, fullPath)
	rel = filepath.ToSlash(rel)
	return rel, int64(len(data)), nil
}

// FullPath 返回相对存储根的完整磁盘路径
func (s *Service) FullPath(relPath string) string {
	return filepath.Join(s.dir, filepath.FromSlash(relPath))
}

// Root 返回存储根目录
func (s *Service) Root() string { return s.dir }

// Delete 删除文件（相对路径）
func (s *Service) Delete(relPath string) error {
	return os.Remove(s.FullPath(relPath))
}

// Stat 返回文件大小
func (s *Service) Stat(relPath string) (int64, error) {
	info, err := os.Stat(s.FullPath(relPath))
	if err != nil {
		return 0, err
	}
	return info.Size(), nil
}

// cleanFileName 清理文件名中的路径分隔符和控制字符
func cleanFileName(name string) string {
	name = strings.ReplaceAll(name, "\\", "_")
	name = strings.ReplaceAll(name, "/", "_")
	name = strings.ReplaceAll(name, ":", "_")
	var b strings.Builder
	for _, r := range name {
		if r >= 32 && r != '<' && r != '>' && r != '"' && r != '|' && r != '*' && r != '?' {
			b.WriteRune(r)
		}
	}
	return strings.TrimSpace(b.String())
}

// AllowTypes 允许的文件扩展名（材料 / 录制 / 标注分别约束）
var AllowTypes = map[string]map[string]bool{
	"materials": {
		".pdf": true, ".doc": true, ".docx": true,
		".xls": true, ".xlsx": true, ".ppt": true, ".pptx": true,
		".txt": true, ".md": true,
		".jpg": true, ".jpeg": true, ".png": true, ".gif": true, ".webp": true,
		".mp4": true, ".webm": true,
		".zip": true,
	},
	"recordings": {".webm": true, ".mp4": true},
	"annotations": {".png": true, ".jpg": true},
}

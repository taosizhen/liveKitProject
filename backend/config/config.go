// Package config 负责加载并管理应用配置
package config

import (
	"fmt"
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

// Config 聚合所有子配置
type Config struct {
	App     AppConfig
	DB      DBConfig
	JWT     JWTConfig
	LiveKit LiveKitConfig
	Storage StorageConfig
	SMTP    SMTPConfig
}

// AppConfig 应用基础配置
type AppConfig struct {
	Env         string
	Port        int
	Name        string
	CORSOrigin  string
	BaseURL     string // 前端访问地址，用于拼接会议链接
	TLSCert     string // HTTPS 证书路径（为空则走 HTTP）
	TLSKey      string // HTTPS 私钥路径
	HTTPPort    int    // 启用 HTTPS 时额外开启的本地回环 HTTP 端口（0 表示关闭）
}

// DBConfig 数据库连接配置（支持 postgres / sqlite）
type DBConfig struct {
	Driver     string // postgres | sqlite
	Host       string
	Port       int
	User       string
	Password   string
	Name       string
	SSLMode    string
	SQLitePath string // sqlite 数据库文件路径
}

// JWTConfig JWT 鉴权配置
type JWTConfig struct {
	Secret           string
	ExpireHours      int
	RefreshExpireDay int
}

// LiveKitConfig LiveKit SFU 连接配置
type LiveKitConfig struct {
	URL       string
	APIKey    string
	APISecret string
}

// StorageConfig 文件存储配置
type StorageConfig struct {
	Dir          string // 存储根目录（相对 backend/）
	MaxSizeBytes int64  // 单文件最大字节数
}

// SMTPConfig 邮件发送配置（QQ 邮箱使用 smtp.qq.com:465 隐式 TLS）
type SMTPConfig struct {
	Host     string
	Port     int
	User     string // SMTP 登录账号（同时作为发件地址）
	Password string // QQ 邮箱为 16 位授权码
	FromName string // 发件人显示名（默认平台名）
}

// Enabled 是否已完成 SMTP 配置；未配置时邮件退化为日志输出（开发模式）
func (s SMTPConfig) Enabled() bool {
	return s.User != "" && s.Password != ""
}

// Load 加载 .env 文件并解析为 Config 结构体
func Load() (*Config, error) {
	_ = godotenv.Load() // 找不到 .env 时静默失败，使用系统环境变量

	cfg := &Config{
		App: AppConfig{
			Env:        getEnv("APP_ENV", "dev"),
			Port:       getEnvInt("APP_PORT", 8080),
			Name:       getEnv("APP_NAME", "meeting-platform"),
			CORSOrigin: getEnv("CORS_ORIGIN", "http://localhost:5173"),
			BaseURL:    getEnv("APP_BASE_URL", "http://localhost:5173"),
			TLSCert:    getEnv("TLS_CERT", ""),
			TLSKey:     getEnv("TLS_KEY", ""),
			HTTPPort:   getEnvInt("APP_HTTP_PORT", 0),
		},
		DB: DBConfig{
			Driver:     getEnv("DB_DRIVER", "postgres"),
			Host:       getEnv("DB_HOST", "localhost"),
			Port:       getEnvInt("DB_PORT", 5432),
			User:       getEnv("DB_USER", "meeting"),
			Password:   getEnv("DB_PASSWORD", "meeting_dev_pass_2026"),
			Name:       getEnv("DB_NAME", "meeting_platform"),
			SSLMode:    getEnv("DB_SSLMODE", "disable"),
			SQLitePath: getEnv("SQLITE_PATH", "./data/meeting.db"),
		},
		JWT: JWTConfig{
			Secret:           getEnv("JWT_SECRET", "dev-secret-change-me"),
			ExpireHours:      getEnvInt("JWT_EXPIRE_HOURS", 24),
			RefreshExpireDay: getEnvInt("JWT_REFRESH_EXPIRE_DAYS", 30),
		},
		LiveKit: LiveKitConfig{
			URL:       getEnv("LIVEKIT_URL", "ws://localhost:7880"),
			APIKey:    getEnv("LIVEKIT_API_KEY", ""),
			APISecret: getEnv("LIVEKIT_API_SECRET", ""),
		},
		Storage: StorageConfig{
			Dir:          getEnv("STORAGE_DIR", "./storage"),
			MaxSizeBytes: int64(getEnvInt("STORAGE_MAX_MB", 50)) * 1024 * 1024,
		},
		SMTP: SMTPConfig{
			Host:     getEnv("SMTP_HOST", "smtp.qq.com"),
			Port:     getEnvInt("SMTP_PORT", 465),
			User:     getEnv("SMTP_USER", ""),
			Password: getEnv("SMTP_PASSWORD", ""),
			FromName: getEnv("SMTP_FROM_NAME", "在线会议协作平台"),
		},
	}

	// 关键配置校验
	if cfg.LiveKit.APIKey == "" || cfg.LiveKit.APISecret == "" {
		fmt.Println("[WARN] LiveKit API Key/Secret 未配置，LiveKit Token 生成功能不可用")
	}

	return cfg, nil
}

// DSN 组装 PostgreSQL 连接串
func (d DBConfig) DSN() string {
	return fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=%s TimeZone=Asia/Shanghai",
		d.Host, d.Port, d.User, d.Password, d.Name, d.SSLMode,
	)
}

// getEnv 读取字符串环境变量，带默认值
func getEnv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// getEnvInt 读取整数环境变量，带默认值
func getEnvInt(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

// Package database 负责 PostgreSQL 连接、自动迁移和种子数据
package database

import (
	"fmt"
	"log"
	"os"
	"path/filepath"

	"meeting-platform/config"
	"meeting-platform/internal/model"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"github.com/glebarez/sqlite" // 纯 Go SQLite 驱动（无 CGO）
)

// DB 全局数据库实例
var DB *gorm.DB

// Init 初始化数据库连接 + 迁移 + 种子（按 DB_DRIVER 选择 postgres 或 sqlite）
func Init(cfg *config.Config) error {
	var dialector gorm.Dialector
	if cfg.DB.Driver == "sqlite" {
		// 确保 SQLite 数据目录存在
		if err := os.MkdirAll(filepath.Dir(cfg.DB.SQLitePath), 0o755); err != nil {
			return fmt.Errorf("create sqlite dir: %w", err)
		}
		dialector = sqlite.Open(cfg.DB.SQLitePath)
	} else {
		dialector = postgres.Open(cfg.DB.DSN())
	}

	var err error
	DB, err = gorm.Open(dialector, &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})
	if err != nil {
		return fmt.Errorf("connect %s: %w", cfg.DB.Driver, err)
	}

	sqlDB, err := DB.DB()
	if err != nil {
		return fmt.Errorf("sql.DB: %w", err)
	}
	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetMaxOpenConns(100)

	if err := autoMigrate(); err != nil {
		return fmt.Errorf("auto migrate: %w", err)
	}

	seedData()

	log.Printf("[DB] %s connected & migrated & seeded\n", cfg.DB.Driver)
	return nil
}

// autoMigrate 自动迁移所有模型
func autoMigrate() error {
	return DB.AutoMigrate(
		&model.Role{},
		&model.Permission{},
		&model.RolePermission{},
		&model.User{},
		&model.Meeting{},
		&model.MeetingParticipant{},
		&model.Recording{},
		&model.Material{},
		&model.ChatMessage{},
	)
}

// seedData 种子数据：初始化角色、权限、默认管理员
func seedData() {
	// 角色
	roles := []model.Role{
		{Name: "admin", Description: "系统管理员"},
		{Name: "teacher", Description: "辅导老师"},
		{Name: "student", Description: "学员"},
	}
	for _, r := range roles {
		var existing model.Role
		if err := DB.Where("name = ?", r.Name).First(&existing).Error; err != nil {
			if err := DB.Create(&r).Error; err == nil {
				log.Printf("[Seed] Role created: %s\n", r.Name)
			}
		}
	}

	// 权限
	permissions := []model.Permission{
		{Name: "user:read", Resource: "user", Action: "read"},
		{Name: "user:write", Resource: "user", Action: "write"},
		{Name: "meeting:create", Resource: "meeting", Action: "create"},
		{Name: "meeting:read", Resource: "meeting", Action: "read"},
		{Name: "meeting:update", Resource: "meeting", Action: "update"},
		{Name: "meeting:delete", Resource: "meeting", Action: "delete"},
		{Name: "meeting:invite", Resource: "meeting", Action: "invite"},
		{Name: "record:start", Resource: "record", Action: "start"},
		{Name: "record:stop", Resource: "record", Action: "stop"},
	}
	for _, p := range permissions {
		var existing model.Permission
		if err := DB.Where("name = ?", p.Name).First(&existing).Error; err != nil {
			if err := DB.Create(&p).Error; err == nil {
				log.Printf("[Seed] Permission created: %s\n", p.Name)
			}
		}
	}

	// 给角色分配权限（简单策略：admin 全权限，teacher 大部分，student 读+加入）
	assignRolePermissions("admin", []string{"user:read", "user:write", "meeting:create", "meeting:read", "meeting:update", "meeting:delete", "meeting:invite", "record:start", "record:stop"})
	assignRolePermissions("teacher", []string{"meeting:create", "meeting:read", "meeting:update", "meeting:invite", "record:start", "record:stop"})
	assignRolePermissions("student", []string{"meeting:read"})

	// 默认管理员账号: admin@demo.com / admin123
	var existingAdmin model.User
	if DB.Where("email = ?", "admin@demo.com").First(&existingAdmin).Error != nil {
		var adminRole model.Role
		if DB.Where("name = ?", "admin").First(&adminRole).Error == nil {
			hash, _ := bcrypt.GenerateFromPassword([]byte("admin123"), bcrypt.DefaultCost)
			admin := model.User{
				Email:        "admin@demo.com",
				PasswordHash: string(hash),
				Name:         "系统管理员",
				RoleID:       adminRole.ID,
				Status:       "active",
			}
			if DB.Create(&admin).Error == nil {
				log.Println("[Seed] Default admin created: admin@demo.com / admin123")
			}
		}
	}
}

// assignRolePermissions 将权限名列表分配给指定角色
func assignRolePermissions(roleName string, permNames []string) {
	var role model.Role
	if DB.Where("name = ?", roleName).First(&role).Error != nil {
		return
	}
	var perms []model.Permission
	if err := DB.Where("name IN ?", permNames).Find(&perms).Error; err != nil {
		return
	}
	// 清空旧关联再重建（简化逻辑）
	DB.Model(&role).Association("Permissions").Clear()
	DB.Model(&role).Association("Permissions").Append(perms)
}

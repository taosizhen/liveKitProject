// Package main 应用入口
package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"meeting-platform/config"
	"meeting-platform/internal/database"
	"meeting-platform/internal/handler"
	"meeting-platform/internal/middleware"
	"meeting-platform/internal/repository"
	"meeting-platform/internal/service"
	"meeting-platform/internal/service/livekitutil"
	jwtutil "meeting-platform/pkg/jwt"
	"meeting-platform/pkg/mailer"
	"meeting-platform/pkg/response"
	"meeting-platform/pkg/storage"
	"meeting-platform/pkg/ws"

	"github.com/gin-gonic/gin"
)

// main 启动 HTTP Server
func main() {
	// 1. 加载配置
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("[FATAL] load config: %v", err)
	}
	log.Printf("[INFO] App: %s, Env: %s, DB: %s\n", cfg.App.Name, cfg.App.Env, cfg.DB.Driver)

	// 2. 初始化数据库
	if err := database.Init(cfg); err != nil {
		log.Fatalf("[FATAL] init db: %v", err)
	}

	// 3. 初始化 JWT 签发器 & 注入到 middleware
	jwtSigner := jwtutil.NewSigner(cfg.JWT.Secret, cfg.JWT.ExpireHours, cfg.JWT.RefreshExpireDay)
	middleware.SetSigner(jwtSigner)

	// 4. 初始化文件存储
	storageSvc, err := storage.NewService(cfg.Storage)
	if err != nil {
		log.Fatalf("[FATAL] init storage: %v", err)
	}
	log.Printf("[INFO] Storage root: %s (max_size: %d MB)\n", storageSvc.Root(), cfg.Storage.MaxSizeBytes/1024/1024)

	// 5. 初始化 WS HubManager（整个进程一个实例）
	hubManager := ws.NewHubManager()

	// 6. LiveKit Service
	livekitService := livekitutil.NewService(&cfg.LiveKit)
	_ = livekitService

	// 7. Repository
	userRepo := repository.NewUserRepository()
	meetingRepo := repository.NewMeetingRepository()
	recRepo := repository.NewRecordingRepository()
	matRepo := repository.NewMaterialRepository()
	chatRepo := repository.NewChatRepository()

	// 8. Service
	authService := service.NewAuthService(userRepo, cfg, jwtSigner)

	// 8.1 邮件发送器 + 会议通知服务（SMTP 未配置时退化为日志输出）
	mailSvc := mailer.New(cfg.SMTP)
	if mailSvc.Enabled() {
		log.Printf("[INFO] SMTP: %s:%d (%s)\n", cfg.SMTP.Host, cfg.SMTP.Port, cfg.SMTP.User)
	} else {
		log.Println("[WARN] SMTP 未配置（SMTP_USER/SMTP_PASSWORD 为空），邮件将输出到日志")
	}
	notifier := service.NewNotificationService(meetingRepo, mailSvc, cfg)

	meetingService := service.NewMeetingService(meetingRepo, userRepo, recRepo, matRepo, storageSvc, notifier)
	recordingService := service.NewRecordingService(recRepo, meetingRepo, userRepo, storageSvc)
	materialService := service.NewMaterialService(matRepo, meetingRepo, userRepo, storageSvc)
	chatService := service.NewChatService(chatRepo, meetingRepo)
	userAdminService := service.NewUserAdminService(userRepo, cfg)

	// 9. Handler
	authHandler := handler.NewAuthHandler(authService)
	meetingHandler := handler.NewMeetingHandler(meetingService, cfg.LiveKit.URL)
	livekitHandler := handler.NewLiveKitHandler(meetingService, cfg.LiveKit.URL, livekitService)
	recordingHandler := handler.NewRecordingHandler(recordingService)
	materialHandler := handler.NewMaterialHandler(materialService, storageSvc)
	chatHandler := handler.NewChatHandler(hubManager, chatService)
	userHandler := handler.NewUserHandler(userAdminService, storageSvc)

	// 10. Router
	r := setupRouter(cfg, jwtSigner, authHandler, meetingHandler, livekitHandler,
		recordingHandler, materialHandler, chatHandler, userHandler)

	// 11. 启动会前提醒调度（每分钟扫描一次，提前 8 小时）
	ctx, cancel := context.WithCancel(context.Background())
	go notifier.StartReminderLoop(ctx)

	// 12. 启动 HTTP/HTTPS Server（配置了 TLS_CERT/TLS_KEY 时启用 HTTPS）
	addr := fmt.Sprintf(":%d", cfg.App.Port)
	log.Printf("[HTTP] Listening on %s (CORS → %s)\n", addr, cfg.App.CORSOrigin)

	srv := &http.Server{Addr: addr, Handler: r}
	go func() {
		var err error
		if cfg.App.TLSCert != "" && cfg.App.TLSKey != "" {
			log.Printf("[HTTP] TLS enabled (cert=%s)\n", cfg.App.TLSCert)
			err = srv.ListenAndServeTLS(cfg.App.TLSCert, cfg.App.TLSKey)
		} else {
			err = srv.ListenAndServe()
		}
		if err != nil && err != http.ErrServerClosed {
			log.Fatalf("[FATAL] http run: %v", err)
		}
	}()

	// 13. 本地回环 HTTP 监听（可选）
	// 背景：Vite 开发服务器以 HTTPS 运行时，其代理转发到 HTTPS 上游会挂起，
	// 故在启用 HTTPS 的场景下额外暴露一个仅 127.0.0.1 可达的 HTTP 端口供代理使用
	var localSrv *http.Server
	if cfg.App.HTTPPort > 0 && cfg.App.TLSCert != "" && cfg.App.TLSKey != "" {
		localAddr := fmt.Sprintf("127.0.0.1:%d", cfg.App.HTTPPort)
		localSrv = &http.Server{Addr: localAddr, Handler: r}
		go func() {
			log.Printf("[HTTP] Loopback HTTP listener on http://%s (for local dev proxy)\n", localAddr)
			if err := localSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				log.Printf("[WARN] loopback http run: %v\n", err)
			}
		}()
	}

	// 优雅关闭
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	cancel()
	if localSrv != nil {
		_ = localSrv.Close()
	}
	log.Println("[INFO] Server shutting down...")
}

// setupRouter 组装 Gin 路由
func setupRouter(
	cfg *config.Config,
	jwtSigner *jwtutil.Signer,
	authHandler *handler.AuthHandler,
	meetingHandler *handler.MeetingHandler,
	livekitHandler *handler.LiveKitHandler,
	recordingHandler *handler.RecordingHandler,
	materialHandler *handler.MaterialHandler,
	chatHandler *handler.ChatHandler,
	userHandler *handler.UserHandler,
) *gin.Engine {
	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(gin.Logger())
	r.Use(middleware.CORS(cfg.App.CORSOrigin))

	// 健康检查
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})

	// 静态文件路由：/storage/*path → 读取 storage.Dir 下对应路径
	r.GET("/storage/*path", materialHandler.Download)

	v1 := r.Group("/api/v1")

	// ============ 公开路由 ============
	auth := v1.Group("/auth")
	{
		auth.POST("/register", authHandler.Register)
		auth.POST("/login", authHandler.Login)
		auth.POST("/refresh", authHandler.Refresh)
	}

	// WebSocket 鉴权通过 query 传入 token，不走 Auth 中间件
	v1.GET("/ws/meetings/:id/chat", chatHandler.JoinWS)

	// ============ 需鉴权 ============
	protected := v1.Group("")
	protected.Use(middleware.Auth(jwtSigner))
	{
		protected.GET("/auth/me", authHandler.Me)

		// 会议
		meetings := protected.Group("/meetings")
		{
			meetings.POST("", meetingHandler.Create)
			meetings.GET("", meetingHandler.List)
			meetings.GET("/:id", meetingHandler.Get)
			meetings.DELETE("/:id", meetingHandler.Cancel)
			meetings.DELETE("/:id/permanent", meetingHandler.Purge)
			meetings.POST("/:id/join", meetingHandler.Join)
			meetings.POST("/:id/invite", meetingHandler.Invite)

			// LiveKit Token
			meetings.GET("/:id/livekit-token", livekitHandler.GetJoinToken)

			// 会议录制
			meetings.POST("/:id/recordings", recordingHandler.Register)
			meetings.POST("/:id/recordings/upload", recordingHandler.Upload)
			meetings.GET("/:id/recordings", recordingHandler.List)

			// 会议材料
			meetings.POST("/:id/materials", materialHandler.Upload)
			meetings.GET("/:id/materials", materialHandler.List)

			// 历史聊天
			meetings.GET("/:id/chat/history", chatHandler.History)
		}

		// 录制管理
		recs := protected.Group("/recordings")
		{
			recs.PATCH("/:id/complete", recordingHandler.Complete)
			recs.DELETE("/:id", recordingHandler.Delete)
		}

		// 材料管理
		protected.DELETE("/materials/:id", materialHandler.Delete)

		// 用户管理（admin only）
		users := protected.Group("/users")
		users.Use(middleware.RequireRole("admin"))
		{
			users.POST("", userHandler.Create)
			users.GET("", userHandler.List)
			users.PATCH("/:id", userHandler.UpdateRoleOrStatus)
			users.DELETE("/:id", userHandler.Delete)
		}

		// 当前用户自助：头像上传（登录即可，不走 admin 校验；独立 /profile 避免与 /users/:id 通配冲突）
		protected.POST("/profile/avatar", userHandler.UploadAvatar)
		protected.PATCH("/profile/name", userHandler.UpdateName)

		// 用户建议列表（所有登录用户可查，用于会议邀请）
		protected.GET("/users/suggest", handler.SuggestUsers)
	}

	// 404 兜底
	r.NoRoute(func(c *gin.Context) {
		response.NotFound(c, "route")
	})

	return r
}

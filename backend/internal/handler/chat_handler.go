package handler

import (
	"log"
	"net/http"
	"strconv"

	"meeting-platform/internal/middleware"
	"meeting-platform/internal/service"
	"meeting-platform/pkg/ws"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

// ChatHandler WebSocket 聊天 + 历史消息 HTTP API
type ChatHandler struct {
	hubManager *ws.HubManager
	svc        *service.ChatService
	// upgrader 复用同一个实例以保留 buffer 池
	upgrader websocket.Upgrader
}

// NewChatHandler 创建
func NewChatHandler(hubManager *ws.HubManager, svc *service.ChatService) *ChatHandler {
	return &ChatHandler{
		hubManager: hubManager,
		svc:        svc,
		upgrader: websocket.Upgrader{
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
			CheckOrigin: func(r *http.Request) bool { return true }, // dev：允许任意 origin
		},
	}
}

// JoinWS GET /api/v1/ws/meetings/:id/chat —— 建立 WebSocket 连接
// 鉴权通过 query 传入：?token=xxx（浏览器端无法在 WS 握手时设置 header）
func (h *ChatHandler) JoinWS(c *gin.Context) {
	meetingID := c.Param("id")

	// 1. 先尝试 Header Bearer token（HTTP 升级场景）；再尝试 query
	claims, ok := middleware.TryGetClaims(c)
	if !ok {
		raw := c.Query("token")
		if raw == "" {
			c.JSON(401, gin.H{"error": "token required"})
			return
		}
		cl, err := middleware.ParseToken(raw)
		if err != nil {
			c.JSON(401, gin.H{"error": "invalid token"})
			return
		}
		claims = cl
	}

	// 2. 升级连接
	conn, err := h.upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("[WS] upgrade fail: %v\n", err)
		return
	}

	hub := h.hubManager.GetOrCreate(meetingID)
	client := &ws.Client{
		Hub:      hub,
		Conn:     conn,
		Send:     make(chan []byte, 256),
		UserID:   claims.UserID,
		UserName: claims.Name,
	}
	hub.Register(client)

	// 启动读写 goroutine
	onChat := func(content string) {
		if _, err := h.svc.Save(meetingID, claims.UserID, content); err != nil {
			log.Printf("[WS] persist fail: %v\n", err)
		}
	}
	go client.WritePump()
	go client.ReadPump(onChat)
}

// History GET /api/v1/meetings/:id/chat/history —— HTTP 拉取历史消息
func (h *ChatHandler) History(c *gin.Context) {
	claims := middleware.GetClaims(c)
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "100"))
	list, err := h.svc.History(claims.UserID, c.Param("id"), limit)
	if err != nil {
		c.JSON(403, gin.H{"error": err.Error()})
		return
	}
	c.JSON(200, list)
}

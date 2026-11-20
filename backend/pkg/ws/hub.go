// Package ws 提供房间级 WebSocket hub：每个会议一个 hub，管理所有客户端并广播消息
package ws

import (
	"encoding/json"
	"log"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
)

// MessageType 消息类型
type MessageType string

const (
	MsgChat       MessageType = "chat"       // 普通聊天
	MsgSystem     MessageType = "system"     // 系统（加入/离开）
	MsgAnnotation MessageType = "annotation" // 标注快照
	MsgPing       MessageType = "ping"       // 心跳
)

// Message WebSocket 消息体
type Message struct {
	Type      MessageType `json:"type"`
	UserID    string      `json:"user_id,omitempty"`
	UserName  string      `json:"user_name,omitempty"`
	Content   string      `json:"content,omitempty"`
	Timestamp int64       `json:"timestamp"`
	// 系统消息可选字段
	Info string `json:"info,omitempty"`
}

// RoomHub 单个会议房间的 hub
type RoomHub struct {
	RoomID    string
	mu        sync.RWMutex
	clients   map[string]*Client // user_id → client
	broadcast chan []byte
	register  chan *Client
	unregister chan *Client
	closed    bool
}

// NewRoomHub 创建房间 hub 并启动
func NewRoomHub(roomID string) *RoomHub {
	h := &RoomHub{
		RoomID:     roomID,
		clients:    make(map[string]*Client),
		broadcast:  make(chan []byte, 256),
		register:   make(chan *Client),
		unregister: make(chan *Client),
	}
	go h.run()
	return h
}

// run 主循环：收注册/注销/广播
func (h *RoomHub) run() {
	for {
		select {
		case c := <-h.register:
			h.mu.Lock()
			if h.closed {
				h.mu.Unlock()
				c.Conn.Close()
				continue
			}
			h.clients[c.UserID] = c
			h.mu.Unlock()
			// 广播系统消息：用户加入
			h.BroadcastSystem(c.UserID, c.UserName, "joined")

		case c := <-h.unregister:
			h.mu.Lock()
			if existing, ok := h.clients[c.UserID]; ok && existing == c {
				delete(h.clients, c.UserID)
				close(c.Send)
				h.BroadcastSystem(c.UserID, c.UserName, "left")
			}
			h.mu.Unlock()

		case msg := <-h.broadcast:
			h.mu.RLock()
			for _, c := range h.clients {
				select {
				case c.Send <- msg:
				default:
					// 发送缓冲区满，跳过（保护广播主循环）
				}
			}
			h.mu.RUnlock()
		}
	}
}

// Register 注册客户端
func (h *RoomHub) Register(c *Client) { h.register <- c }

// Unregister 注销客户端
func (h *RoomHub) Unregister(c *Client) { h.unregister <- c }

// Broadcast 将消息广播给房间内所有客户端
func (h *RoomHub) Broadcast(msg Message) {
	if msg.Timestamp == 0 {
		msg.Timestamp = time.Now().UnixMilli()
	}
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}
	h.broadcast <- data
}

// BroadcastChat 发送聊天消息
func (h *RoomHub) BroadcastChat(userID, userName, content string) {
	h.Broadcast(Message{
		Type:      MsgChat,
		UserID:    userID,
		UserName:  userName,
		Content:   content,
		Timestamp: time.Now().UnixMilli(),
	})
}

// BroadcastSystem 发送系统消息
func (h *RoomHub) BroadcastSystem(userID, userName, action string) {
	h.Broadcast(Message{
		Type:      MsgSystem,
		UserID:    userID,
		UserName:  userName,
		Info:      action,
		Timestamp: time.Now().UnixMilli(),
	})
}

// BroadcastAnnotation 广播标注快照（base64 或 URL）
func (h *RoomHub) BroadcastAnnotation(userID, userName, content string) {
	h.Broadcast(Message{
		Type:      MsgAnnotation,
		UserID:    userID,
		UserName:  userName,
		Content:   content,
		Timestamp: time.Now().UnixMilli(),
	})
}

// ClientCount 房间当前客户端数
func (h *RoomHub) ClientCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients)
}

// Close 关闭 hub
func (h *RoomHub) Close() {
	h.mu.Lock()
	defer h.mu.Unlock()
	for _, c := range h.clients {
		c.Conn.Close()
	}
	h.closed = true
}

// ============================================================
// 全局 HubManager（多房间管理）
// ============================================================

// HubManager 管理所有房间 hub
type HubManager struct {
	mu   sync.RWMutex
	hubs map[string]*RoomHub // room_id → hub
}

// NewHubManager 创建全局 hub manager
func NewHubManager() *HubManager {
	return &HubManager{hubs: make(map[string]*RoomHub)}
}

// GetOrCreate 获取或创建房间 hub
func (m *HubManager) GetOrCreate(roomID string) *RoomHub {
	m.mu.RLock()
	if h, ok := m.hubs[roomID]; ok {
		m.mu.RUnlock()
		return h
	}
	m.mu.RUnlock()

	m.mu.Lock()
	defer m.mu.Unlock()
	if h, ok := m.hubs[roomID]; ok {
		return h
	}
	h := NewRoomHub(roomID)
	m.hubs[roomID] = h
	return h
}

// Remove 删除空房间 hub
func (m *HubManager) Remove(roomID string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if h, ok := m.hubs[roomID]; ok && h.ClientCount() == 0 {
		h.Close()
		delete(m.hubs, roomID)
		log.Printf("[WS] room %s hub removed\n", roomID)
	}
}

// ActiveRooms 当前活跃房间数
func (m *HubManager) ActiveRooms() int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return len(m.hubs)
}

// Client 单连接客户端
type Client struct {
	Hub      *RoomHub
	Conn     *websocket.Conn
	Send     chan []byte
	UserID   string
	UserName string
}

// ReadPump 读取消息并回显/处理（阻塞 goroutine）
func (c *Client) ReadPump(onChat func(content string)) {
	defer func() {
		c.Hub.Unregister(c)
		c.Conn.Close()
	}()
	c.Conn.SetReadLimit(1 << 20) // 1MB
	for {
		_, data, err := c.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway) {
				log.Printf("[WS] read error: %v\n", err)
			}
			return
		}
		var msg Message
		if err := json.Unmarshal(data, &msg); err != nil {
			continue
		}
		switch msg.Type {
		case MsgChat:
			if onChat != nil {
				onChat(msg.Content)
			}
			c.Hub.Broadcast(msg)
		case MsgPing:
			// 心跳由 WritePump 处理 pong
		}
	}
}

// WritePump 写消息循环（阻塞 goroutine）
func (c *Client) WritePump() {
	ticker := time.NewTicker(30 * time.Second)
	defer func() {
		ticker.Stop()
		c.Conn.Close()
	}()
	for {
		select {
		case msg, ok := <-c.Send:
			c.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				c.Conn.WriteMessage(websocket.CloseMessage, nil)
				return
			}
			w, err := c.Conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(msg)
			// 队列中还有就继续（合并帧）
			n := len(c.Send)
			for i := 0; i < n; i++ {
				w.Write([]byte{'\n'})
				w.Write(<-c.Send)
			}
			if err := w.Close(); err != nil {
				return
			}
		case <-ticker.C:
			c.Conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
			if err := c.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// IsValidUUID 检查字符串是否为有效 UUID（工具函数）
func IsValidUUID(s string) bool {
	_, err := uuid.Parse(s)
	return err == nil
}

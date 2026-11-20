# 技术架构文档

> 版本：v1.0 · 最后更新：2026-01

---

## 1. 总体架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                        用户浏览器                                    │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  React 18 + Vite + TS + TailwindCSS + Zustand              │    │
│  │  @livekit/components-react@2.9.25                           │    │
│  └────────────┬────────────────────┬──────────────────────────┘    │
│               │ HTTPS/JWT          │ WebSocket                      │
└───────────────┼─────────────────────┼──────────────────────────────┘
                │                     │
┌───────────────┼─────────────────────┼──────────────────────────────┐
│               ▼                     ▼                              │
│  ┌───────────────────┐   ┌──────────────────────┐                  │
│  │   Go Gin 后端      │   │  LiveKit Server      │                  │
│  │   :8080            │   │  :7880 (WS)          │                  │
│  │                    │   │                      │                  │
│  │  Auth/JWT/RBAC     │   │  SFU 音视频转发       │                  │
│  │  会议/用户/材料/录制 │   │  Room 管理           │                  │
│  │  文件存储           │   │  Webhook 回调        │                  │
│  └─────────┬─────────┘   └──────────────────────┘                  │
│            │                                                       │
│   进程内 GORM                                                      │
│            │                                                       │
│            ▼                                                       │
│  ┌───────────────────┐                                             │
│  │ SQLite / PostgreSQL│                                             │
│  │  meeting.db       │                                             │
│  └───────────────────┘                                             │
│                                                                    │
│  服务器：Windows 原生运行（WSL/Docker 可选）                        │
└────────────────────────────────────────────────────────────────────┘
```

---

## 2. 技术栈

### 2.1 前端

| 技术 | 版本 | 用途 |
|---|---|---|
| React | 18.x | UI 框架 |
| TypeScript | 5.x | 类型安全 |
| Vite | 5.4 | 构建工具（dev server + 生产打包） |
| TailwindCSS | 3.x | 原子化 CSS |
| Zustand | 4.x | 轻量状态管理（authStore / meetingStore / chatStore） |
| Axios | 1.x | HTTP 客户端，带拦截器自动解包 ApiResponse |
| React Router | 6.x | 路由 + RequireAuth / RequireAdmin 守卫 |
| @livekit/components-react | 2.9.25 | 音视频组件（Room / AudioRenderer / VideoRenderer） |
| livekit-client | 2.x | LiveKit WebRTC SDK |
| lucide-react | latest | 图标库 |

### 2.2 后端

| 技术 | 版本 | 用途 |
|---|---|---|
| Go | 1.26 | 主语言 |
| Gin | latest | HTTP 框架 |
| GORM | latest | ORM（AutoMigrate 自动建表） |
| glebarez/sqlite | v1.11 | 纯 Go SQLite 驱动（零外部依赖） |
| google/uuid | latest | 应用层生成 UUID（兼容 sqlite/postgres） |
| gorilla/websocket | latest | WebSocket（会议内聊天） |
| golang-jwt/jwt | latest | JWT Access/Refresh Token 签发 |
| LiveKit | v1.13.11（源码编译） | SFU 媒体服务器 |

### 2.3 运行环境

| 组件 | 端口 | 说明 |
|---|---|---|
| 前端 dev | 5173 | Vite dev server（HMR） |
| 前端生产 | 任意 | `frontend/dist` 静态资源 |
| Go 后端 | 8080 | HTTP + WebSocket |
| LiveKit Server | 7880 (WS) / 7881 (TCP fallback) | SFU 媒体转发 |
| PostgreSQL（可选） | 5433 | Docker 容器，默认不用 |
| SQLite | — | `backend/data/meeting.db`（默认） |

---

## 3. 后端分层架构

```
cmd/server/main.go          ← 入口，组装所有依赖 + 启动 HTTP
config/config.go            ← 环境变量配置加载
        │
        ▼
internal/
  ├── handler/              ← HTTP Handler（Gin Context → 业务层 → 响应）
  │   ├── auth_handler.go
  │   ├── meeting_handler.go   ← Invite + SuggestUsers
  │   ├── livekit_handler.go   ← LiveKit Join Token 下发
  │   ├── recording_handler.go
  │   ├── material_handler.go
  │   ├── chat_handler.go      ← WebSocket 握手 + HTTP 历史
  │   └── user_handler.go      ← admin only
  ├── service/              ← 业务逻辑（组织者校验 / 幂等邀请）
  │   ├── service.go          ← MeetingService / InviteParticipants
  │   └── service_ext.go      ← RecordingService / MaterialService / ChatService / UserAdminService
  ├── repository/           ← 数据访问层（GORM 封装）
  │   └── repository.go
  ├── middleware/           ← Auth / CORS / RBAC
  │   └── middleware.go
  ├── model/                ← GORM 模型 + AutoMigrate
  │   └── model.go
  └── database/database.go  ← DB_DRIVER 选择 sqlite/postgres

pkg/                         ← 可复用工具包
  ├── jwt/jwt.go             ← Signer（Access + Refresh Token）
  ├── response/response.go   ← 统一响应 {code, message, data}
  ├── storage/storage.go     ← 文件存储（白名单 + 大小限制）
  ├── ws/hub.go              ← HubManager + RoomHub + Client（gorilla/websocket）
  └── utils/rand.go
```

---

## 4. 数据模型 ER 图

```
┌──────────────┐       role_id       ┌──────────────┐
│    users      │────────────────────│    roles      │
└──────┬───────┘                     └──────────────┘
       │
       │ organizer_id          ┌──────────────────┐
       ├──────────────────────▶│     meetings      │
       │                       └──────┬───────────┘
       │                              │ meeting_id
       │                              ▼
       │                       ┌──────────────────────┐
       │                       │ meeting_participants │
       │                       └──────────────────────┘
       │
       │ user_id
       │
       ├────────────────────────────────────────────┐
       │                                            │
       ▼                                            ▼
┌───────────────┐                          ┌───────────────┐
│ chat_messages  │                          │   materials   │
└───────────────┘                          └───────────────┘

                meeting_id
                     ▼
            ┌───────────────┐
            │  recordings   │
            └───────────────┘
```

### 主要表字段速查

| 表名 | 主键 | 关键字段 |
|---|---|---|
| users | id (varchar(36)) | email, password_hash, name, role_id, status(active/disabled) |
| roles | id | name(admin/teacher/student), permissions (many2many) |
| meetings | id | title, description, organizer_id, start_time, end_time, status, meeting_type, room_name, settings(jsonb) |
| meeting_participants | id | meeting_id, user_id, participant_role(host/speaker/attendee), status(invited/confirmed/joined) |
| chat_messages | id | meeting_id, user_id, content, created_at |
| materials | id | meeting_id, uploader_id, file_name, file_url, file_size |
| recordings | id | meeting_id, livekit_recording_id, file_url, duration_sec, status |

---

## 5. 前端架构

```
src/
├── router/index.tsx          ← 路由定义 + RequireAuth / RequireAdmin 守卫
├── store/                     ← Zustand stores
│   ├── authStore.ts          ← tokens + user info
│   ├── meetingStore.ts       ← 会议列表缓存
│   └── chatStore.ts          ← WebSocket 实时消息 + 历史
├── api/                       ← HTTP 客户端
│   ├── http.ts               ← Axios 实例 + 拦截器（自动解包 ApiResponse）
│   ├── auth.ts
│   └── meeting.ts            ← inviteParticipants / suggestUsers
├── types/index.ts             ← 全局 TS 类型
├── pages/
│   ├── Auth/Login.tsx        ← 登录页
│   ├── Auth/Register.tsx     ← 注册页
│   ├── Dashboard/Dashboard.tsx ← 工作台
│   ├── Meetings/MeetingList.tsx    ← 会议列表
│   ├── Meetings/MeetingCreate.tsx  ← 创建会议
│   ├── Meetings/MeetingDetail.tsx  ← 会议详情（含 Tab + 邀请入口）
│   ├── Room/Room.tsx         ← LiveKit 会议室
│   ├── Admin/UserManagement.tsx ← 用户管理（admin）
│   └── NotFound.tsx
├── components/
│   ├── Invite/InviteDialog.tsx   ← 邀请参会者弹窗（搜索+多选+提交）
│   ├── Chat/ChatPanel.tsx
│   ├── Materials/MaterialPanel.tsx
│   └── Layout/Layout.tsx
└── main.tsx                  ← 入口
```

---

## 6. 鉴权与权限

```
客户端                                       后端
  │                                            │
  │ POST /api/v1/auth/login                    │
  │ {email, password}                          │
  │ ─────────────────────────────────────────▶│
  │                                            │ bcrypt 校验
  │                                            │ 签发 Access Token (24h)
  │                                            │ 签发 Refresh Token (30d)
  │ ◀─────────────────────────────────────────│
  │ {access_token, refresh_token}              │
  │                                            │
  │ 后续请求 Header:                            │
  │ Authorization: Bearer <access_token>       │
  │ ─────────────────────────────────────────▶│
  │                                            │ middleware.Auth 解析 JWT
  │                                            │ middleware.RequireRole("admin")
  │                                            │ 或业务层校验 organizer_id
```

### LiveKit Token 下发流程
```
前端请求：GET /api/v1/meetings/:id/livekit-token
    │
    ▼
后端校验：
  1. 当前用户是会议 organizer 或 participant
  2. 用 LIVEKIT_API_KEY + LIVEKIT_API_SECRET 签发 LiveKit Join Token
    │
    ▼
前端用 token 连接 ws://localhost:7880 → 进入 Room
```

---

## 7. 文件存储

- 存储目录：`backend/storage/`（由 `STORAGE_DIR` 环境变量配置）
- 白名单后缀：`.pdf`, `.doc`, `.docx`, `.ppt`, `.pptx`, `.xls`, `.xlsx`, `.png`, `.jpg`, `.jpeg`, `.gif`, `.zip`, `.txt`
- 大小限制：`STORAGE_MAX_SIZE_MB`（默认 50MB）
- 访问路由：`GET /storage/*path` → 直接读取文件

---

## 8. WebSocket（会议内聊天）

```
前端（参会者）                         后端 HubManager
  │                                       │
  │ WS GET /api/v1/ws/meetings/:id/chat?token=<jwt>
  │ ─────────────────────────────────────▶│
  │                                       │ 校验 token + 解析 meeting_id
  │                                       │ 查找/创建 RoomHub
  │                                       │ 注册 Client
  │ 双向消息通道建立                        │
  │ ◀────────────────────────────────────▶│
  │                                       │
  │ send: {type: "chat", content: "..."}  │ Hub 广播给同 Room 所有 Client
  │ ─────────────────────────────────────▶│
```

- 后端用 gorilla/websocket 实现，ReadPump/WritePump 双 goroutine + 30s 心跳
- 断线自动重连由前端 livekit-client / ws 客户端处理

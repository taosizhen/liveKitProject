# 开发指南 · 代码功能简介

> 版本：v1.0 · 最后更新：2026-01

---

## 1. 项目目录结构

```
liveKitProject/
├── backend/                   ← Go 后端
│   ├── cmd/server/main.go     ← 入口
│   ├── config/config.go       ← 配置加载（env）
│   ├── internal/
│   │   ├── handler/           ← HTTP Handler（8 个文件）
│   │   ├── service/           ← 业务逻辑层
│   │   ├── repository/        ← GORM 数据访问
│   │   ├── middleware/        ← Auth / CORS / RBAC
│   │   ├── model/             ← GORM 模型定义
│   │   └── database/          ← DB 连接初始化
│   ├── pkg/                   ← 可复用包
│   │   ├── jwt/               ← JWT 签发器
│   │   ├── response/          ← 统一响应
│   │   ├── storage/           ← 文件存储
│   │   ├── mailer/            ← SMTP 邮件发送（465 隐式 TLS / 587 STARTTLS）
│   │   ├── ws/                ← WebSocket Hub
│   │   └── utils/             ← 工具函数
│   ├── data/meeting.db        ← SQLite 数据库文件
│   ├── .env                   ← 环境配置
│   ├── go.mod
│   └── server.exe             ← 编译产物
│
├── frontend/                  ← React 前端
│   ├── src/
│   │   ├── router/            ← 路由 + 守卫
│   │   ├── store/             ← Zustand stores
│   │   ├── api/               ← Axios HTTP 客户端
│   │   ├── types/             ← TS 类型
│   │   ├── pages/             ← 页面组件
│   │   ├── components/        ← 业务组件
│   │   │   ├── Room/AnnotationLayer.tsx  ← 标注层（静态标记/激光笔/白板，Data Channel 同步）
│   │   │   ├── Chat/ChatPanel.tsx        ← 会议内聊天
│   │   │   └── Materials/MaterialPanel.tsx← 会议材料
│   │   ├── hooks/
│   │   │   └── useRoomRecorder.ts        ← 客户端 canvas 合成录制（视频+标注+水印+时间戳）
│   │   └── main.tsx
│   ├── index.html
│   ├── vite.config.ts
│   ├── tailwind.config.js
│   └── package.json
│
├── deploy/                    ← LiveKit 部署相关
│   ├── livekit.yaml           ← LiveKit Server 配置
│   ├── bin/livekit-server.exe ← 编译好的 Windows LiveKit Server
│   └── livekit-src/           ← LiveKit 源码（参考/可重编译）
│
├── doc/                       ← 项目文档
│   ├── PRD.md
│   ├── ARCHITECTURE.md
│   ├── API.md
│   ├── DEVELOPMENT.md         ← 本文件
│   └── DEPLOYMENT.md
│
└── docker-compose.yml         ← 可选：PostgreSQL + 其他
```

---

## 2. 启动开发环境

### 2.1 前置依赖

| 依赖 | 版本要求 | 说明 |
|---|---|---|
| Go | ≥ 1.22 | 后端 |
| Node.js | ≥ 18 | 前端（推荐 v24） |
| npm | ≥ 9 | 前端包管理 |
| LiveKit Server | v1.13.x | 已编译在 `deploy/bin/livekit-server.exe` |
| Docker（可选） | — | 仅 PostgreSQL 时需要 |

### 2.2 启动顺序

```powershell
# 步骤 1：LiveKit Server（Windows 原生）
cd d:\CODE\WOAN\liveKitProject
.\deploy\bin\livekit-server.exe --config .\deploy\livekit.yaml
# 输出：starting LiveKit server on version=1.13.x ... Listening on :7880

# 步骤 2：Go 后端
cd .\backend
.\server.exe
# 输出：[INFO] App: meeting-platform, Env: dev, DB: sqlite
#       [HTTP] Listening on :8080

# 步骤 3：React 前端
cd ..\frontend
npm.cmd run dev
# 输出：Local:   http://localhost:5173/
```

> 💡 三个进程分别开三个 PowerShell 窗口，或用 `Start-Process` 后台启动。

### 2.3 种子账号

| 角色 | 邮箱 | 密码 |
|---|---|---|
| admin | admin@demo.com | admin123 |

> 注册接口也可以创建新账号。数据库为 SQLite，首次启动时 GORM AutoMigrate 自动建表 + 写入 seed 数据。

### 2.4 端口清单

| 服务 | 端口 | 访问地址 |
|---|---|---|
| 前端 dev | 5173 | http://localhost:5173 |
| 后端 API | 8080 | http://localhost:8080/api/v1 |
| 健康检查 | 8080 | http://localhost:8080/health |
| LiveKit WS | 7880 | ws://localhost:7880 |
| LiveKit TCP fallback | 7881 | tcp://localhost:7881 |

---

## 3. 后端开发指引

### 3.1 编译

```powershell
cd backend
go build -o server.exe ./cmd/server
# 或直接运行
go run ./cmd/server
```

### 3.2 新增一个 API 的步骤

1. **Model**（如需要新表）：在 `internal/model/model.go` 添加结构体，嵌入 `BaseModel`
2. **Repository**：在 `internal/repository/repository.go` 添加对应的 Repository 结构体
3. **Service**：在 `internal/service/service.go` 或 `service_ext.go` 新增方法（写业务校验）
4. **Handler**：在 `internal/handler/` 下的文件中新增 Handler 方法，签名 `func (h *XxxHandler) Method(c *gin.Context)`
5. **Router**：在 `cmd/server/main.go` 的 `setupRouter` 中挂载路由
6. **自动建表**：`database.Init` 里的 `db.AutoMigrate(&model.YourModel{})` 加上

### 3.3 配置项（`.env`）

```
APP_ENV=dev
APP_PORT=8080
APP_NAME=meeting-platform
CORS_ORIGIN=http://localhost:5173

DB_DRIVER=sqlite
SQLITE_PATH=./data/meeting.db
# DB_DRIVER=postgres 时用下面四个
DB_HOST=172.27.178.198
DB_PORT=5433
DB_USER=meeting
DB_PASSWORD=meeting_dev_pass_2026
DB_NAME=meeting_platform
DB_SSLMODE=disable

JWT_SECRET=change-me-in-production-please-use-rsa-keys
JWT_EXPIRE_HOURS=24
JWT_REFRESH_EXPIRE_DAYS=30

LIVEKIT_URL=ws://localhost:7880
LIVEKIT_API_KEY=5a4c8e9f2b7d4a1b
LIVEKIT_API_SECRET=c47f9b2a8e6d3c1b5a9f2e7d4b6c8a1f
```

### 3.4 关键设计点

- **UUID 生成**：应用层 `uuid.New()` 在 `BeforeCreate` 钩子中生成，兼容 sqlite/postgres（不能用 PG 的 `gen_random_uuid()`）
- **CORS**：`middleware.CORS` 同时支持 `*`、完整 origin、`*.localhost` 通配
- **Auth 中间件**：解析 JWT 后将 claims 存入 `gin.Context`，业务层用 `middleware.GetClaims(c)` 读取
- **组织权限校验**：在 Service 层做 `meeting.OrganizerID.String() != organizerID` 判断，而非 Handler 层

---

## 4. 前端开发指引

### 4.1 开发命令

```powershell
cd frontend
npm.cmd install          # 首次安装依赖
npm.cmd run dev          # 开发模式（HMR）
npm.cmd run build        # 生产构建
npm.cmd run preview      # 预览生产构建
npx.cmd tsc --noEmit     # 仅做类型检查
```

### 4.2 统一 HTTP 客户端

`src/api/http.ts` 封装 Axios，**前端不需要自己解包 ApiResponse**：

```typescript
// http.ts 的拦截器已把 axiosResponse.data 直接返回
// 业务代码直接断言为 ApiResponse<业务体>
export function getMeeting(id: string) {
  return http.get(`/meetings/${id}`) as unknown as Promise<ApiResponse<Meeting>>;
}
```

### 4.3 新增页面的步骤

1. `src/pages/YourFeature.tsx` — 创建页面组件
2. `src/router/index.tsx` — 在路由表中新增路由
3. 如需鉴权，用 `RequireAuth` 包裹；管理员页用 `RequireAdmin`
4. 如需侧边栏入口，在 `components/Layout/Layout.tsx` 中添加菜单项

### 4.4 状态管理选型

| 场景 | 推荐 |
|---|---|
| 全局用户信息（登录态） | `authStore`（Zustand） |
| 会议列表缓存 | `meetingStore`（Zustand） |
| WebSocket 消息队列 | `chatStore`（Zustand） |
| 单次弹窗状态 | 组件内部 `useState` |

### 4.5 会议详情页加载 —— 正确模式

**❌ 错误写法（之前的 bug）**：
```tsx
// useState 惰性初始化只执行一次同步函数，reload() 的 setState 可能被吞掉
useState(() => { reload(); return null; });
```

**✅ 正确写法**：
```tsx
useEffect(() => {
  reload();
}, [id]);  // id 变化时重新加载
```

### 4.6 LiveKit 组件使用

参考 Room.tsx 的模式：
```tsx
// 1. 先请求后端拿 LiveKit Token
const info = await meetingApi.getLiveKitJoinInfo(meetingId);

// 2. 连接 LiveKit
const { connect, disconnect } = useRoom({
  adapter: new LiveKitRoom(info.livekit_url),
});
await connect(info.token);

// 3. 渲染组件树
<Room>
  <VideoRenderer />
  <AudioRenderer />
  <ScreenShare />
</Room>
```

---

## 5. 常见问题 FAQ

**Q1：页面空白，只有"加载中..."怎么办？**
检查浏览器控制台是否有 401/403。如果会议详情页一直加载，看后端 console 有没有 API 报错。也可以直接 `curl http://localhost:8080/health` 确认后端存活。

**Q2：邀请按钮不显示？**
只有会议组织者能看到「邀请参会者」按钮（`isOrganizer = currentUser?.id === meeting.organizer_id`）。先确认当前登录账号是否为创建该会议的用户。

**Q3：LiveKit 连接不上？**
1. 确认 `deploy/bin/livekit-server.exe` 正在运行
2. 确认后端 `.env` 中 `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` 与 `deploy/livekit.yaml` 中 `keys` 部分完全一致
3. 检查 Windows 防火墙是否拦截了 7880/7881 端口

**Q4：SQLite 和 PostgreSQL 如何切换？**
改后端 `.env` 中 `DB_DRIVER=sqlite` → `DB_DRIVER=postgres` 并填写 PG 连接信息。切换后首次启动 GORM 会 AutoMigrate 建表。

**Q5：WebSocket 聊天连接失败？**
WebSocket 握手不能带 `Authorization` Header，所以 token 放在 query string：
```
ws://localhost:8080/api/v1/ws/meetings/<meeting_id>/chat?token=<access_token>
```

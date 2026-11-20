# 在线会议协助平台（Meeting Platform）

基于 **LiveKit** 的在线会议平台：**React Web 端 + Flutter 移动端 + Go 后端**。
支持会议预约与邀请、实时音视频、屏幕共享、实时标注、会议材料、聊天、录制合成，
并实现了「动态主持人、静音入会、语音自动切主位、举手点名、同框圆桌、远程控制」等增强能力。

> 设计文档：[功能增强实现计划](.trae/documents/会议平台四大功能增强-实现计划.md) ｜
> 高保真原型：[design-prototype/meeting-ui-prototype.html](design-prototype/meeting-ui-prototype.html)

---

## 功能特性

### 会议基础能力
- 账号体系与角色（`admin` / `teacher` / `student`），JWT 登录 + 刷新令牌
- 会议创建、列表、详情、邀请、取消、彻底删除
- 音视频通话、屏幕共享、会议内聊天（WebSocket）、会议材料上传/下载
- 实时标注（静态标记 / 激光笔 / 白板），基于 LiveKit Data Channel 同步
- 客户端 canvas 合成录制（视频 + 标注 + 水印 + 时间戳）
- 个人头像上传（Web 侧边栏 / App 个人资料页）

### 本轮增强的四项能力
| # | 能力 | 说明 |
|---|---|---|
| ① | **同框圆桌 ⇄ 参会列表小地图** | 全员席位沿圆桌圆周均布（圆形头像/视频，不抠图）；圆桌与参会列表互为小地图，点击互换全屏 |
| ② | **动态主持人 + 静音入会 + 语音切主位** | 全员静音入会；第一个进会者为主持人，`teacher/admin` 进会自动接任，其下线后回到在场最早加入者；谁说话自动把画面切到主位并高亮 |
| ③ | **举手 + 主持人点名** | 举手列表按时间排序；主持人「邀请发言」后，被点名端麦克风自动开启 |
| ④ | **远程控制** | 仅 PC 控制 PC：共享屏幕方授权后，控制端可操作对方桌面（键盘/鼠标/滚轮） |

### 动态主持人规则（跨端确定性一致，零后端状态）
主持人 = 在场成员（含本地）按以下顺序排序后的第一位：

1. 角色权重：`admin` / `teacher` = 0，`student` = 1
2. 加入时间 `joinedAt` 升序
3. `identity` 字典序兜底

角色与头像通过 LiveKit token 的 `metadata`（`{"role":"...","avatar_url":"..."}`）下发，
Web 端与 Flutter 端各自本地推导，不依赖后端状态。

---

## 技术栈

| 层 | 技术 |
|---|---|
| Web 前端 | React 18、TypeScript、Vite、TailwindCSS、Zustand、React Router、`@livekit/components-react` |
| 移动端 | Flutter 3、Riverpod、go_router、Dio、`livekit_client`、flutter_secure_storage |
| 后端 | Go（Gin、GORM、SQLite/PostgreSQL、JWT、gorilla/websocket、LiveKit Server SDK） |
| 实时音视频 | LiveKit Server（自建，Windows 本地运行） |
| 桌面代理 | Go + `golang.org/x/sys/windows`（`SendInput` 注入）、gorilla/websocket |
| 部署 | Caddy（HTTPS 反代）/ Docker Compose 可选 |

---

## 目录结构

```
liveKitProject/
├── backend/                  # Go 后端（Gin）
│   ├── cmd/server/           # 入口
│   ├── internal/             # handler / service / repository / middleware / model
│   ├── pkg/                  # jwt / response / storage / mailer / ws / utils
│   ├── config/  migrations/  scripts/
│   └── .env.example
├── frontend/                 # React Web 端
│   └── src/
│       ├── pages/Room/       # 会议室页面
│       ├── components/Room/  # 标注层 / 成员列表 / 同框圆桌 / 小地图 / 远程控制层
│       ├── hooks/            # 录制、动态主持人、Data Channel、信令
│       ├── store/            # 认证 / 举手信令 / 远程控制状态
│       └── services/         # 本地桌面代理客户端
├── meeting_mobile/           # Flutter 移动端
│   └── lib/
│       ├── features/room/    # 会控、标注、信令、圆桌
│       ├── data/  core/  models/
├── desktop-agent/            # 远程控制桌面代理（Windows，Go 单文件）
├── deploy/                   # LiveKit 配置、TLS 代理、Windows 版 server
├── design-prototype/         # 可交互 HTML 设计原型
├── doc/                      # PRD / 架构 / API / 开发 / 部署文档
├── docker/  docker-compose.yml  Makefile
└── .trae/documents/          # 本轮功能增强实现计划
```

---

## 环境要求

| 依赖 | 版本 | 说明 |
|---|---|---|
| Node.js / npm | ≥ 18 / ≥ 9 | 前端 |
| **Go** | ≥ 1.22 | 后端与桌面代理 |
| Flutter SDK | ≥ 3.3 | 移动端（仓库内已在 `.toolchain/` 本地安装） |
| LiveKit Server | v1.13.x | 已编译在 `deploy/bin/`（需本地下载，不入库） |
| git-bash / PowerShell | — | Windows 开发环境 |

> **重要约定：本地 Windows 未安装 Go，所有 Go 命令必须在 WSL 中执行**
> 例如 `wsl go build ./...`、`wsl go run ./cmd/server`。
> WSL 通过 `/mnt/d/CODE/WOAN/liveKitProject` 访问同一份项目目录。

---

## 快速开始

### 1. 后端（在 WSL 中执行）

```bash
# 配置
cd /mnt/d/CODE/WOAN/liveKitProject/backend
cp .env.example .env          # 按需修改数据库 / LiveKit / JWT 配置

# 编译校验
wsl go build ./...            # Windows 侧执行等价命令

# 启动（默认 :8080）
wsl go run ./cmd/server
```

SQLite 为默认存储（`backend/data/meeting.db`），无需额外数据库；
如需 PostgreSQL，将 `DB_DRIVER` 改为 `postgres` 并填写连接信息。

### 2. 前端

```powershell
cd d:\CODE\WOAN\liveKitProject\frontend
npm install
npm run dev      # https://localhost:5173（Vite 已配置 mkcert 自签证书）
```

### 3. LiveKit Server 与 TLS 代理（Windows）

```powershell
# 音视频服务（:7880）
cd d:\CODE\WOAN\liveKitProject\deploy
.\bin\livekit-server.exe --config livekit.yaml

# 浏览器 HTTPS 页面需要 wss，LiveKit 原生不支持信令 TLS，
# 故通过 7891 的 TLS 终止代理转发
node livekit-tls-proxy.cjs
```

| 服务 | 默认端口 |
|---|---|
| 前端 Vite dev | 5173（HTTPS） |
| 后端 API | 8080 |
| LiveKit 信令/媒体 | 7880 |
| LiveKit TLS 代理（wss） | 7891 |

端口以 `backend/.env`、`deploy/livekit.yaml`、`frontend/vite.config.ts` 为准。

### 4. 移动端（Flutter）

```powershell
$env:PUB_CACHE='D:\CODE\WOAN\liveKitProject\.toolchain\pub-cache'
& 'D:\CODE\WOAN\liveKitProject\.toolchain\flutter\bin\flutter.bat' pub get
& 'D:\CODE\WOAN\liveKitProject\.toolchain\flutter\bin\flutter.bat' run
```

启动前按需修改 `meeting_mobile/assets/config.json` 中的后端地址。

### 5. 远程控制桌面代理（被控端 PC，可选）

```bash
# 在 WSL 中交叉编译 Windows 可执行文件
wsl bash -c "cd /mnt/d/CODE/WOAN/liveKitProject/desktop-agent && GOPROXY=https://goproxy.cn,direct go mod tidy && GOOS=windows CGO_ENABLED=0 GOARCH=amd64 go build -o desktop-agent.exe ."
```

```powershell
# 被控端在 Windows 上运行
.\desktop-agent.exe
```

代理特性与安全边界：

- 仅监听回环地址 `127.0.0.1:17653`，不接受外部连接
- 会话需一次性 token（`POST /session` 创建，30 秒有效、单会话、握手即消费）
- 启动时声明 DPI 感知，避免 125%/150% 缩放下坐标偏移
- 全局快捷键 **Ctrl+Alt+Esc** 可随时强制结束被控会话

> 说明：最初计划使用 robotgo，但其依赖 CGO，无法在 WSL 中交叉编译 Windows 程序，
> 现改为 `golang.org/x/sys/windows` 直接调用 `user32.SendInput`（纯 Go，`CGO_ENABLED=0` 可编译）。

---

## 配置说明（`backend/.env`）

| 变量 | 说明 | 示例 |
|---|---|---|
| `APP_PORT` | 后端监听端口 | `8080` |
| `CORS_ORIGIN` | 允许的前端 Origin | `http://localhost:5173` |
| `DB_DRIVER` | `sqlite`（默认）/ `postgres` | `sqlite` |
| `SQLITE_PATH` | SQLite 文件路径 | `./data/meeting.db` |
| `JWT_SECRET` / `JWT_EXPIRE_HOURS` | JWT 密钥与有效期 | `24` |
| `LIVEKIT_URL` | LiveKit 地址 | `ws://localhost:7880` |
| `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` | LiveKit 凭证（需与 `deploy/livekit.yaml` 一致） | — |

完整模板见 [backend/.env.example](backend/.env.example)。

---

## API 概览

统一前缀 `/api/v1`，除标注「公开」外均需 `Authorization: Bearer <token>`。

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/auth/register` `/auth/login` `/auth/refresh` | 公开：注册 / 登录 / 刷新令牌 |
| GET | `/auth/me` | 当前用户 |
| GET/POST | `/meetings` | 会议列表 / 创建 |
| GET/DELETE | `/meetings/:id` | 详情 / 取消 |
| DELETE | `/meetings/:id/permanent` | 彻底删除（管理员） |
| POST | `/meetings/:id/join` `/invite` | 加入 / 邀请 |
| GET | `/meetings/:id/livekit-token` | 获取 LiveKit 入会凭证（含角色+头像 metadata） |
| POST/GET | `/meetings/:id/materials` | 上传 / 列出会议材料 |
| GET | `/meetings/:id/chat/history` | 聊天历史 |
| WS | `/ws/meetings/:id/chat` | 会议聊天长连接 |
| POST/GET | `/meetings/:id/recordings` | 登记 / 列出录制 |
| POST | `/profile/avatar` | **上传头像**（返回新 URL） |
| GET | `/users` `/users/suggest` | 用户管理（管理员） / 邀请建议 |
| GET | `/health`、`/storage/*path` | 公开：健康检查 / 静态文件 |

详细字段与示例见 [doc/API.md](doc/API.md)。

---

## Data Channel 协议

会议室内高频交互通过 LiveKit Data Channel（reliable）以 JSON 信封 `{src, k, ts, ...}` 分域传输：

| topic | 用途 |
|---|---|
| `annotation` | 实时标注（已有能力，协议保持不变） |
| `signal` | 举手 / 放下手 / 举手状态同步 / 主持人点名 / 点名回执 |
| `remote_control` | 远程控制请求、授权、输入事件、心跳、结束 |

信令采用**纯内存 + 事件溯源**（不落库）：新加入成员连接后约 500ms 广播同步请求，
正在举手的成员重发举手消息完成收敛；成员离线即移除。

---

## 测试账号

| 角色 | 账号 | 密码 | 说明 |
|---|---|---|---|
| 教师 | `teacher@test.com` | `123456` | 进会自动接任主持人，可发起远程控制 |
| 学生 | `student@test.com` | `123456` | 静音入会、举手、被点名开麦 |

> 按动态主持人规则，老师/管理员进入会自动接任主持人，测试「普通参会者体验」请用学生账号。

---

## 开发与验证

```bash
# 后端（WSL，本地 Windows 未安装 Go）
wsl go build ./...

# 前端类型检查
cd frontend && npx tsc --noEmit

# 移动端静态检查
$env:PUB_CACHE='D:\CODE\WOAN\liveKitProject\.toolchain\pub-cache'
& 'D:\CODE\WOAN\liveKitProject\.toolchain\flutter\bin\flutter.bat' analyze
```

`frontend` 中 `src/api/http.ts` 存在两处 `import.meta.env` 类型缺失的历史告警，与业务逻辑无关。

---

## 相关文档

- [doc/PRD.md](doc/PRD.md) — 产品需求
- [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md) — 架构设计
- [doc/API.md](doc/API.md) — 接口文档
- [doc/DEVELOPMENT.md](doc/DEVELOPMENT.md) — 开发指南
- [doc/DEPLOYMENT.md](doc/DEPLOYMENT.md) — 部署说明
- [.trae/documents/会议平台四大功能增强-实现计划.md](.trae/documents/会议平台四大功能增强-实现计划.md) — 本轮增强实现计划与自测清单

---

## 已知限制

- 远程控制仅支持 **PC 控制 PC**；移动端只观看，不参与控制
- 被控端必须运行 `desktop-agent.exe`，否则控制端会收到 `no_agent` 并看到引导提示
- 头像上传后需**重新入会**生效（角色/头像随 token metadata 下发）
- 移动端不提供桌面代理，Flutter analyze 中存在 `material.dart` 弃用提示（历史问题，info 级）

# 部署指南

> 版本：v1.0 · 最后更新：2026-01

---

## 1. 三种部署模式总览

| 模式 | 适用场景 | 复杂度 |
|---|---|---|
| **Windows 原生**（推荐本地开发） | 开发/演示 | 低 |
| **Docker Compose**（可选） | 仅需要 PostgreSQL | 中 |
| **生产服务器** | 正式上线 | 高 |

---

## 2. Windows 原生部署（推荐开发模式）

### 2.1 前置条件
- Windows 10/11
- Go 1.22+ 或已编译好的 `server.exe`
- Node.js 18+
- LiveKit Server v1.13.x（已在 `deploy/bin/` 中编译）

### 2.2 步骤

```powershell
# === 步骤 1：LiveKit Server ===
cd d:\CODE\WOAN\liveKitProject
.\deploy\bin\livekit-server.exe --config .\deploy\livekit.yaml
# 输出中看到 "Listening on :7880" 即成功

# === 步骤 2：后端（新终端）===
cd d:\CODE\WOAN\liveKitProject\backend
# 方式 A：直接编译并运行
go build -o server.exe ./cmd/server
.\server.exe
# 方式 B：go run 快速调试
go run ./cmd/server

# === 步骤 3：前端（新终端）===
cd d:\CODE\WOAN\liveKitProject\frontend
npm.cmd install          # 首次或依赖变更时
npm.cmd run dev          # 开发模式
# 或生产构建
npm.cmd run build        # 产物在 frontend/dist/
```

### 2.3 验证
- 打开 http://localhost:5173 → 看到登录页
- 登录 admin@demo.com / admin123 → 进入工作台
- http://localhost:8080/health → `{"status":"ok"}`

### 2.4 生产部署（Windows）

```powershell
# 后端编译
cd backend
go build -ldflags="-s -w" -o server.exe ./cmd/server

# 前端构建 + 用任意静态服务器托管
cd frontend
npm.cmd run build
# 然后用 nginx / caddy / iis 等托管 frontend/dist/
```

---

## 3. Docker Compose（可选 PostgreSQL）

> 如果只用 SQLite，可以跳过这一节。

`docker-compose.yml` 提供 PostgreSQL 可选容器：

```yaml
services:
  postgres:
    image: postgres:15-alpine
    container_name: meeting-postgres
    environment:
      POSTGRES_USER: meeting
      POSTGRES_PASSWORD: meeting_dev_pass_2026
      POSTGRES_DB: meeting_platform
    ports:
      - "5433:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
volumes:
  pgdata:
```

### 启动

```powershell
# WSL 中或 Docker Desktop
docker compose up -d postgres

# 后端 .env 切换
# DB_DRIVER=postgres
# DB_HOST=127.0.0.1  (Docker Desktop) 或 WSL VM IP
# DB_PORT=5433
# DB_USER=meeting
# DB_PASSWORD=meeting_dev_pass_2026
# DB_NAME=meeting_platform
```

---

## 4. LiveKit Server 配置详解

`deploy/livekit.yaml`（v1.13 schema）：

```yaml
port: 7880

logging:
  level: info

rtc:
  udp_port: 7882        # WebRTC UDP
  tcp_port: 7881        # TCP fallback（防火墙严格的网络用）

# API 密钥：与后端 .env 中完全一致
keys:
  5a4c8e9f2b7d4a1b: c47f9b2a8e6d3c1b5a9f2e7d4b6c8a1f

# 录制相关（可选）
recordings:
  output:
    local:
      output_dir: ./data/recordings
```

### 密钥安全说明
生产环境**必须更换** LiveKit API Key/Secret 和 JWT Secret：
```bash
# 生成随机密钥（Linux/Mac）
openssl rand -hex 16   # API Key
openssl rand -hex 32   # API Secret / JWT Secret
```

同步更新：
1. `deploy/livekit.yaml` 中 `keys` 部分
2. `backend/.env` 中 `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` / `JWT_SECRET`

---

## 4.1 邮件通知配置（QQ 邮箱 SMTP）

会议创建邀请邮件和会前 8 小时提醒依赖 SMTP，配置在 `backend/.env`：

```env
SMTP_HOST=smtp.qq.com
SMTP_PORT=465
SMTP_USER=your_account@qq.com    # 发件 QQ 邮箱
SMTP_PASSWORD=xxxxxxxxxxxxxxxx   # 16 位授权码（不是 QQ 登录密码）
SMTP_FROM_NAME=在线会议协作平台
APP_BASE_URL=http://localhost:5173   # 邮件内入会按钮链接的前端地址
```

**获取 QQ 邮箱授权码**：
1. 登录 QQ 邮箱 → 设置 → 账户
2. 开启「POP3/SMTP 服务」，按提示生成 16 位授权码
3. 将授权码填入 `SMTP_PASSWORD`，重启后端生效

**说明**：
- 端口 465 使用隐式 TLS；若改用 587 会自动走 STARTTLS
- `SMTP_USER` / `SMTP_PASSWORD` 留空时，邮件内容只打印到后端日志（`[MAIL-DEV]`），适合本地联调
- 发件人显示名为会议组织者姓名，`Reply-To` 为组织者邮箱；实际投递账号仍是平台 SMTP 账号
- 会前提醒由后端每分钟扫描一次，无需额外的定时任务或外部 cron

---

## 5. 生产环境部署建议

### 5.1 进程管理

| 组件 | Windows | Linux |
|---|---|---|
| Go 后端 | NSSM / Windows 服务 | systemd |
| LiveKit Server | NSSM / Windows 服务 | systemd |
| 前端静态资源 | IIS / Caddy / Nginx | Nginx / Caddy |

systemd 示例（Linux）：
```ini
# /etc/systemd/system/meeting-backend.service
[Unit]
Description=Meeting Platform Backend
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/meeting/backend
EnvironmentFile=/opt/meeting/backend/.env
ExecStart=/opt/meeting/backend/server
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

### 5.2 Nginx 反向代理（前端 + API）

```nginx
server {
    listen 80;
    server_name meeting.yourdomain.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name meeting.yourdomain.com;

    ssl_certificate     /etc/letsencrypt/live/...;
    ssl_certificate_key /etc/letsencrypt/live/...;

    # 前端静态
    location / {
        root /opt/meeting/frontend/dist;
        try_files $uri $uri/ /index.html;
    }

    # 后端 API
    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # LiveKit WebSocket
    location /rtc {
        proxy_pass http://127.0.0.1:7880;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

### 5.3 数据库迁移

SQLite 切换到 PostgreSQL 时：
1. 备份 SQLite 数据
2. 修改 `.env` 中 `DB_DRIVER=postgres` 及连接信息
3. 首次启动 GORM AutoMigrate 自动建表
4. 如需历史数据迁移，可写一次性脚本从 SQLite 读入 PG

### 5.4 安全检查清单

- [ ] JWT Secret 更换为 32 字节随机值
- [ ] LiveKit API Key/Secret 更换
- [ ] `.env` 文件加入 `.gitignore`
- [ ] CORS_ORIGIN 改为生产域名
- [ ] HTTPS 证书（Let's Encrypt）
- [ ] 文件上传目录定期清理（storage/recordings/materials）
- [ ] 数据库定期备份

---

## 6. 常见部署问题

### Q1：LiveKit Server 在 WSL2 内运行时 WebRTC 不通
Windows 的 Hyper-V 虚拟交换机会转发 UDP 端口，但 flClash / Hyper-V 防火墙双重过滤可能导致丢包。
**解决方案**：在 Windows 原生运行 LiveKit Server，不走 WSL。

### Q2：PostgreSQL 从 Docker 暴露到主机不稳定
WSL mirrored NAT + Hyper-V 防火墙会拦截。建议：
- `.wslconfig` 设置 `networkingMode=NAT` + `firewall=false`
- 或直接用 SQLite 绕过

### Q3：生产环境 LiveKit 连接数多了怎么办？
LiveKit 官方支持横向扩展，接入 Redis 做节点发现即可实现 SFU 集群。参考 [LiveKit 官方文档](https://docs.livekit.io)。

### Q4：如何备份数据？
```powershell
# SQLite
Copy-Item backend\data\meeting.db backup_$(Get-Date -Format yyyyMMdd).db

# PostgreSQL
pg_dump -h localhost -p 5433 -U meeting meeting_platform > backup.sql
```

# REST API 接口文档

> 版本：v1.0 · 最后更新：2026-01
> Base URL：`http://localhost:8080/api/v1`
> 统一响应格式：`{ code: number, message: string, data?: T, error?: {...} }` ，`code=0` 表示成功

---

## 1. 认证（公开接口）

### 1.1 注册
```
POST /api/v1/auth/register
Content-Type: application/json
```

**请求体**：
```json
{
  "email": "teacher@demo.com",
  "password": "admin123",
  "name": "张老师",
  "role": "teacher"  // 可选，默认 student
}
```

**响应** `201`：
```json
{
  "code": 0,
  "message": "created",
  "data": {
    "id": "uuid-string",
    "email": "teacher@demo.com",
    "name": "张老师",
    "role_name": "teacher"
  }
}
```

---

### 1.2 登录
```
POST /api/v1/auth/login
```

**请求体**：
```json
{ "email": "admin@demo.com", "password": "admin123" }
```

**响应** `200`：
```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "tokens": {
      "access_token": "eyJ...",
      "refresh_token": "eyJ...",
      "expires_in": 86400,
      "token_type": "Bearer"
    },
    "user": {
      "id": "uuid",
      "email": "admin@demo.com",
      "name": "Admin",
      "role": "admin"
    }
  }
}
```

---

### 1.3 刷新 Token
```
POST /api/v1/auth/refresh
```

**请求体**：
```json
{ "refresh_token": "eyJ..." }
```

**响应**：同登录 `tokens` 结构。

---

### 1.4 获取当前用户
```
GET /api/v1/auth/me
Authorization: Bearer <access_token>
```

---

## 2. 会议

### 2.1 创建会议
```
POST /api/v1/meetings
Authorization: Bearer <access_token>
```

**请求体**：
```json
{
  "title": "Python 基础辅导",
  "description": "一对一辅导第 3 次课",
  "start_time": "2026-01-15T14:00:00Z",
  "end_time": "2026-01-15T15:00:00Z",
  "meeting_type": "tutoring",
  "participant_ids": ["uuid-of-student-1", "uuid-of-student-2"]
}
```

**响应** `201`：
```json
{
  "code": 0,
  "message": "created",
  "data": { /* Meeting 对象 */ }
}
```

---

### 2.2 会议列表
```
GET /api/v1/meetings?page=1&page_size=20&status=scheduled
```

| 参数 | 类型 | 说明 |
|---|---|---|
| page | int | 页码，默认 1 |
| page_size | int | 每页数量，默认 20，最大 100 |
| status | string | 可选：scheduled / in_progress / completed / cancelled |

**响应** `200`：
```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "items": [ /* Meeting[] */ ],
    "total": 42,
    "page": 1,
    "page_size": 20,
    "pages": 3
  }
}
```

---

### 2.3 会议详情
```
GET /api/v1/meetings/:id
```

**响应** `200`：
```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "id": "uuid",
    "title": "...",
    "organizer_id": "uuid",
    "organizer": { "id": "...", "name": "...", "email": "..." },
    "status": "scheduled",
    "start_time": "2026-01-15T14:00:00Z",
    "participants": [
      {
        "id": "uuid",
        "user_id": "uuid",
        "user": { "id": "...", "name": "...", "email": "..." },
        "participant_role": "attendee",
        "status": "invited"
      }
    ],
    "created_at": "...",
    "updated_at": "..."
  }
}
```

---

### 2.4 取消会议
```
DELETE /api/v1/meetings/:id
```

仅组织者可取消。

---

### 2.4.1 彻底删除会议（会后清理）⭐
```
DELETE /api/v1/meetings/:id/permanent
Authorization: Bearer <access_token>
```

**权限**：组织者或管理员
**前置条件**：会议已结束（`status` 为 `completed` / `cancelled`，或当前时间已过 `end_time`）

**行为**：在同一事务内硬删除会议及其参会人员、聊天记录、录制、材料记录，
并同步删除磁盘上的录制视频与材料文件（不可恢复）。

**响应** `200`：
```json
{
  "code": 0,
  "message": "ok",
  "data": { "deleted_recordings": 1, "deleted_materials": 3 }
}
```

**失败示例**：
```json
{ "code": 20005, "message": "meeting not ended yet, cannot delete" }
```

---

### 2.5 标记加入
```
POST /api/v1/meetings/:id/join
```

参会者确认接受邀请。

**响应**：`{ "code": 0, "data": { "status": "joined" } }`

---

### 2.6 邀请参会者 ⭐
```
POST /api/v1/meetings/:id/invite
Content-Type: application/json
Authorization: Bearer <access_token>
```

**请求体**：
```json
{
  "participant_ids": [
    "uuid-of-user-1",
    "uuid-of-user-2"
  ]
}
```

**校验规则**：
- 必须是会议 **组织者**（organizer_id === 当前用户）
- 不能邀请自己（organizer 跳过）
- 已在会中的用户幂等跳过
- 被邀请用户必须存在且 status=active

**响应** `200`：
```json
{
  "code": 0,
  "message": "ok",
  "data": { "added": 2 }
}
```

---

### 2.7 LiveKit 入会 Token
```
GET /api/v1/meetings/:id/livekit-token
```

**响应** `200`：
```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "livekit_url": "ws://localhost:7880",
    "token": "eyJ...",
    "room_name": "meeting-room-uuid",
    "meeting_id": "uuid"
  }
}
```

---

## 3. 会议录制

### 3.1 注册录制
```
POST /api/v1/meetings/:id/recordings
```

**请求体**：
```json
{
  "livekit_recording_id": "rec-id-123",
  "status": "recording"
}
```

### 3.2 录制列表
```
GET /api/v1/meetings/:id/recordings
```

### 3.3 完成录制
```
PATCH /api/v1/recordings/:id/complete
```

**请求体**：
```json
{
  "file_url": "/storage/recordings/xxx.mp4",
  "duration_sec": 1800,
  "file_size_bytes": 52428800,
  "status": "completed"
}
```

### 3.4 删除录制
```
DELETE /api/v1/recordings/:id
```

### 3.5 上传浏览器录制文件
```
POST /api/v1/meetings/:id/recordings/upload
Content-Type: multipart/form-data
```

**表单字段**：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| file | File | 录制文件，支持 `.webm` / `.mp4` |
| duration_sec | int | 录制时长（秒） |

**说明**：前端使用 `canvas.captureStream()` + `MediaRecorder` 在浏览器端合成画面
（视频 + 标注 + 会议水印 + 实时时间戳），停止录制后上传该文件并生成 `completed` 状态的录制记录。

**响应示例**：
```json
{
  "code": 0,
  "message": "created",
  "data": {
    "id": "rec-uuid",
    "meeting_id": "meeting-uuid",
    "file_url": "/storage/recordings/2026-11-11/xxx_meeting-xxx.webm",
    "duration_sec": 24,
    "file_size_bytes": 4615950,
    "status": "completed"
  }
}
```

---

## 4. 会议材料

### 4.1 上传材料
```
POST /api/v1/meetings/:id/materials
Content-Type: multipart/form-data
```

| 字段 | 类型 | 说明 |
|---|---|---|
| file | file | 文件本体（白名单后缀 + 大小限制） |

**响应** `201`：
```json
{
  "code": 0,
  "data": {
    "id": "uuid",
    "meeting_id": "uuid",
    "file_name": "python_notes.pdf",
    "file_url": "/storage/materials/xxx.pdf",
    "file_type": "pdf",
    "file_size": 2048000
  }
}
```

### 4.2 材料列表
```
GET /api/v1/meetings/:id/materials
```

### 4.3 删除材料
```
DELETE /api/v1/materials/:id
```

### 4.4 下载材料（静态路由）
```
GET /storage/materials/xxx.pdf
```
由 Gin 直接从磁盘读取，不走鉴权中间件（通过 material 文件内部校验）。

---

## 5. 聊天

### 5.1 WebSocket 握手（实时）
```
WS GET /api/v1/ws/meetings/:id/chat?token=<access_token>
```
query 参数传入 JWT，不走 Auth 中间件（HTTP Upgrade 无法带 Header）。

消息格式：
```json
{
  "type": "chat",
  "content": "大家好",
  "user_id": "uuid",
  "user_name": "张三",
  "timestamp": 1736971200
}
```

### 5.2 历史聊天记录
```
GET /api/v1/meetings/:id/chat/history
```

---

## 6. 用户管理（Admin Only）

所有 `/api/v1/users` 下的接口都带 `middleware.RequireRole("admin")`。

### 6.1 创建用户
```
POST /api/v1/users
```
**请求体**：
```json
{
  "email": "student1@demo.com",
  "password": "123456",
  "name": "学员一",
  "role_name": "student"
}
```

### 6.2 用户列表
```
GET /api/v1/users?page=1&page_size=20&role_name=student
```

### 6.3 修改角色或状态
```
PATCH /api/v1/users/:id
```
**请求体**（二选一）：
```json
{ "role_name": "teacher" }
// 或
{ "status": "disabled" }
```

### 6.4 删除用户
```
DELETE /api/v1/users/:id
```

---

## 7. 用户建议（登录用户可查）

### 7.1 搜索可邀请用户
```
GET /api/v1/users/suggest?q=张
```
返回系统中所有 status=active 的用户列表，支持 name 或 email 的模糊匹配。

**响应**：
```json
{
  "code": 0,
  "data": [
    { "id": "uuid", "name": "张老师", "email": "zhang@demo.com", "role_name": "teacher" },
    { "id": "uuid", "name": "张三",   "email": "zhangsan@demo.com", "role_name": "student" }
  ]
}
```

---

## 8. 邮件通知（无独立接口，随会议创建自动触发）

### 8.1 触发时机

| 场景 | 触发方式 | 说明 |
|---|---|---|
| 会议创建成功 | 后端异步发送 | 给全部参会者（不含组织者）发送会议邀请邮件 |
| 会前 8 小时 | 后端每分钟扫描一次 | 会议创建时间距开始 ≥ 8 小时时补发提醒；< 8 小时时跳过提醒 |

- 发件人显示名 = 创建会议人员姓名，`Reply-To` = 组织者邮箱，实际投递账号为平台 SMTP
- 邮件正文含会议名称、会议时间、组织者、会议描述，以及「查看会议详情 / 进入会议」按钮
- 去重字段：`notified_at`（创建通知）、`reminder_sent_at`（会前提醒），重复触发不会重复发送
- SMTP 未配置时邮件内容仅打印到后端日志（`[MAIL-DEV]`），不会真实投递

---

## 9. 其他

### 9.1 健康检查
```
GET /health
```
返回 `{ "status": "ok" }`，不带 API 前缀。

### 9.2 统一错误格式
```json
{
  "code": 40001,
  "message": "forbidden: only organizer can invite",
  "error": { "type": "forbidden", "detail": "..." }
}
```

### 错误码速查

| 码 | 含义 |
|---|---|
| 0 | 成功 |
| 400xx | 参数校验失败 |
| 401xx | 未登录 / Token 无效 |
| 403xx | 无权限 |
| 404xx | 资源不存在 |
| 500xx | 服务端内部错误 |
| 20001 | 创建会议失败 |
| 20002 | 取消会议失败 |
| 20003 | 加入会议失败 |
| 20004 | 邀请参会者失败 |
| 20005 | 彻底删除会议失败（未结束 / 无权限） |

# syntax=docker/dockerfile:1.6
# -----------------------------------------------------------
# 多阶段构建：Go 1.26 编译 → Alpine 运行
# 说明：后端用 SQLite，零外部数据库依赖，单二进制即可运行
# -----------------------------------------------------------

# ===== 阶段 1：编译 =====
FROM golang:1.26-alpine AS builder

# 构建依赖（CGO 必需：SQLite 纯 Go 驱动不需要 CGO）
RUN apk add --no-cache git ca-certificates

WORKDIR /src

# 先拷贝 go.mod / go.sum 利用 Docker 层缓存
COPY go.mod go.sum ./
RUN go mod download

# 拷贝全部源码（.dockerignore 已排除 data/、storage/、web/）
COPY . .

# 交叉编译：静态链接，无 CGO，体积最小
#   CGO_ENABLED=0  → SQLite 纯 Go 驱动，无需 C 链接器
#   -trimpath      → 去除编译机绝对路径
#   -ldflags=-s -w → 去符号表，减少 30% 体积
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" \
    -o /out/server ./cmd/server

# ===== 阶段 2：运行 =====
FROM alpine:3.20

# 时区 / CA 证书（SMTP 发邮件 + HTTPS 请求必需）
RUN apk add --no-cache ca-certificates tzdata \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

WORKDIR /app

# 仅拷贝编译产物，镜像极小（~15MB）
COPY --from=builder /out/server /app/server
COPY --from=builder /src/.env.example /app/.env.example

# 运行时数据目录（SQLite + 会议材料 + 录制文件）
RUN mkdir -p /app/data /app/storage/recordings /app/storage/materials /app/web

EXPOSE 8080

# 健康检查：访问内置 /api/v1/health
HEALTHCHECK --interval=15s --timeout=3s --retries=3 --start-period=5s \
  CMD wget -qO- http://127.0.0.1:8080/api/v1/health || exit 1

CMD ["/app/server"]

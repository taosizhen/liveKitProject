# =========================================================
# Meeting Platform — Makefile（纯 WSL 本地，无 Docker 拉镜像依赖）
# ---------------------------------------------------------
# 一键构建 + 启动全栈（前提：WSL 已装 Go / Node.js / curl）：
#
#   前端 React (Vite) → npm run build → dist 拷到 backend/web/
#   后端 Go (Gin)       → go build → Linux 二进制 backend/build/server
#   Caddy 反代 HTTPS    → curl 下载 caddy 单文件 → 启动在 443/80
#   LiveKit             → 继续用宿主机 deploy/bin/livekit-server.exe
#
# 快速上手：
#   make build-frontend          # 第一次跑（npm install + build + 拷 dist）
#   make build-backend-linux     # 编译 Linux 二进制（给 Caddy/HTTPS 反代用）
#   make download-caddy          # 下载 caddy（第一次跑，~30MB）
#   make up                      # 一键起 backend + caddy
#   make logs                    # 看两个后台进程日志
#   make down                    # 停掉
#   make clean                   # 删所有构建产物
# =========================================================

# ---------- 工具 ----------
GO            ?= go
NPM           ?= npm
CURL          ?= curl

# ---------- 绝对路径（避免 cd 之后相对路径出错） ----------
ROOT_DIR      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
FRONTEND_DIR  := $(ROOT_DIR)/frontend
BACKEND_DIR   := $(ROOT_DIR)/backend
BUILD_DIR     := $(BACKEND_DIR)/build
WEB_DIR       := $(BACKEND_DIR)/web
DIST_DIR      := $(FRONTEND_DIR)/dist
CADDY_DIR     := $(ROOT_DIR)/docker/caddy
CADDY_BIN     := $(CADDY_DIR)/caddy
CADDY_URL     := https://caddyserver.com/api/download?os=linux&arch=amd64
CADDY_LOG     := $(CADDY_DIR)/caddy.log
SERVER_LOG    := $(BUILD_DIR)/server.log
PID_DIR       := $(ROOT_DIR)/.pids

# ---------- 默认目标 ----------
.DEFAULT_GOAL := help

.PHONY: help build-frontend build-backend-linux build-backend-win \
        download-caddy build-all \
        up down restart logs status clean \
        dev dev-frontend dev-backend dev-livekit

## help: 列出所有可用命令
help:
	@echo "Meeting Platform — 一键构建/启动"
	@echo "========================================"
	@grep -E '^## ' $(MAKEFILE_LIST) \
	 | sed 's/^## //' \
	 | awk -F ':' '{printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# =========================================================
#  构建
# =========================================================

## build-frontend: npm run build → dist 拷到 backend/web/
build-frontend:
	@mkdir -p $(WEB_DIR)
	@echo "==> npm install & build"
	@cd $(FRONTEND_DIR) && $(NPM) install --no-audit --no-fund 2>&1 | tail -3
	@cd $(FRONTEND_DIR) && $(NPM) run build 2>&1 | tail -5
	@echo "==> 拷贝 $(DIST_DIR) → $(WEB_DIR)"
	@rm -rf $(WEB_DIR)/*
	@cp -r $(DIST_DIR)/* $(WEB_DIR)/
	@echo "✅ 前端 → $(WEB_DIR)"

## build-backend-linux: 编译 Linux 二进制（无 CGO，静态链接）
build-backend-linux:
	@mkdir -p $(BUILD_DIR)
	@echo "==> CGO_ENABLED=0 go build → $(BUILD_DIR)/server"
	@cd $(BACKEND_DIR) && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
		$(GO) build -trimpath -ldflags="-s -w" \
		-o build/server ./cmd/server
	@echo "✅ $(BUILD_DIR)/server ($(shell ls -lh $(BUILD_DIR)/server | awk '{print $$5}'))"

## build-backend-win: 交叉编译 Windows exe（给宿主机直接跑）
build-backend-win:
	@echo "==> GOOS=windows go build → backend/server.exe"
	@cd $(BACKEND_DIR) && GOOS=windows GOARCH=amd64 CGO_ENABLED=0 \
		$(GO) build -trimpath -ldflags="-s -w" \
		-o server.exe ./cmd/server
	@echo "✅ backend/server.exe"

## download-caddy: 下载 Caddy 单文件（仅首次需要，~50MB）
download-caddy:
	@if [ -x $(CADDY_BIN) ]; then \
		echo "Caddy 已存在 $(CADDY_BIN)，跳过"; \
	else \
		echo "==> 下载 Caddy → $(CADDY_BIN)"; \
		mkdir -p $(CADDY_DIR); \
		$(CURL) -fsSL "$(CADDY_URL)" -o $(CADDY_BIN) && chmod +x $(CADDY_BIN); \
		echo "✅ Caddy ready: $(shell $(CADDY_BIN) version 2>/dev/null | head -1)"; \
	fi

## build-all: 依次 build-frontend + build-backend-linux + download-caddy
build-all: build-frontend build-backend-linux download-caddy

# =========================================================
#  启停（后台进程，PID 存 .pids/）
# =========================================================

## up: 一键起 backend + caddy（LiveKit 需另外手动启动）
up: build-all
	@echo "==> 启动 backend + caddy"
	@mkdir -p $(PID_DIR) $(BACKEND_DIR)/data $(BACKEND_DIR)/storage/recordings $(BACKEND_DIR)/storage/materials
	@# ---- backend ----
	@if [ -f $(PID_DIR)/server.pid ] && kill -0 $$(cat $(PID_DIR)/server.pid) 2>/dev/null; then \
		echo "  backend 已在运行 (pid $$(cat $(PID_DIR)/server.pid))"; \
	else \
		echo "  启动 backend → 8080"; \
		cd $(BACKEND_DIR) && nohup ./build/server > $(SERVER_LOG) 2>&1 & echo $$! > $(PID_DIR)/server.pid; \
	fi
	@# ---- caddy ----
	@if [ -f $(PID_DIR)/caddy.pid ] && kill -0 $$(cat $(PID_DIR)/caddy.pid) 2>/dev/null; then \
		echo "  caddy 已在运行 (pid $$(cat $(PID_DIR)/caddy.pid))"; \
	else \
		echo "  启动 caddy → 443/80"; \
		cd $(CADDY_DIR) && nohup $(CADDY_BIN) run --config Caddyfile --adapter caddyfile > $(CADDY_LOG) 2>&1 & echo $$! > $(PID_DIR)/caddy.pid; \
	fi
	@sleep 2
	@echo ""
	@echo "✅ 已启动！"
	@echo "   前端 HTTPS:   https://192.168.100.101:8443"
	@echo "   HTTP 跳转:    http://192.168.100.101:8081 → HTTPS"
	@echo "   健康检查:     curl -k https://127.0.0.1:8443/api/v1/health"
	@echo "   backend pid=$$(cat $(PID_DIR)/server.pid 2>/dev/null)"
	@echo "   caddy  pid=$$(cat $(PID_DIR)/caddy.pid 2>/dev/null)"
	@echo ""
	@echo "   ⚠️  LiveKit 需单独启动（宿主机）："
	@echo "      cd deploy && .\bin\livekit-server.exe --config livekit.yaml"

## down: 停止 backend + caddy
down:
	@echo "==> 停止进程"
	@for svc in server caddy; do \
		pidfile=$(PID_DIR)/$$svc.pid; \
		if [ -f $$pidfile ]; then \
			pid=$$(cat $$pidfile); \
			if kill -0 $$pid 2>/dev/null; then \
				kill $$pid && sleep 1 && echo "  stopped $$svc (pid $$pid)"; \
			fi; \
			rm -f $$pidfile; \
		fi; \
	done
	@echo "✅ 已停止"

## restart: down + up
restart: down up

## logs: 实时 tail backend + caddy 日志
logs:
	@tail -f $(SERVER_LOG) $(CADDY_LOG)

## status: 查看进程状态 + 端口
status:
	@echo "=== 进程 ==="
	@for svc in server caddy; do \
		pidfile=$(PID_DIR)/$$svc.pid; \
		if [ -f $$pidfile ]; then \
			pid=$$(cat $$pidfile); \
			if kill -0 $$pid 2>/dev/null; then \
				echo "  ✅ $$svc  running  pid=$$pid"; \
			else \
				echo "  ❌ $$svc  dead     (stale pidfile)"; \
			fi; \
		else \
			echo "  ➖ $$svc  not started"; \
		fi; \
	done
	@echo ""
	@echo "=== 端口 ==="
	@ss -tlnp 2>/dev/null | grep -E ':(8080|8443|8081|7880)' || true
	@echo ""
	@echo "=== 健康检查 ==="
	@curl -sk https://127.0.0.1:8443/api/v1/health 2>/dev/null || echo "  Caddy/backend 尚未就绪"

# =========================================================
#  开发模式（本地裸跑，不走 HTTPS / Caddy）
# =========================================================

## dev: 分别启动三件套的指引
dev:
	@echo "请开三个终端分别执行："
	@echo "  1. make dev-backend       (Go API :8080)"
	@echo "  2. make dev-frontend      (Vite  :5173)"
	@echo "  3. make dev-livekit       (LiveKit :7880)"

## dev-frontend: Vite dev server（http://localhost:5173）
dev-frontend:
	@cd $(FRONTEND_DIR) && $(NPM) run dev

## dev-backend: Go 本地 go run（:8080）
dev-backend:
	@cd $(BACKEND_DIR) && $(GO) run ./cmd/server

## dev-livekit: 宿主机 LiveKit Server（Windows）
dev-livekit:
	@echo "请在 Windows PowerShell 执行："
	@echo "  cd deploy && .\bin\livekit-server.exe --config livekit.yaml"

# =========================================================
#  清理
# =========================================================

## clean: 删前端 dist、backend/build、backend/web、.pids
clean: down
	@echo "==> 删除构建产物"
	-@rm -rf $(DIST_DIR) $(BUILD_DIR) $(WEB_DIR) $(PID_DIR)
	@echo "✅ 清理完成（SQLite / storage / caddy 二进制保留）"

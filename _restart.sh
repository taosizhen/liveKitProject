#!/bin/bash
# 彻底清理 → 起 backend + caddy → 立刻验证
# 用 setsid 彻底脱离当前 shell 会话（避免 SIGHUP 杀进程）
set -e

ROOT=/mnt/d/CODE/WOAN/liveKitProject
echo "==> 清理残留"
ps -eo pid,comm | awk '$2=="server"||$2=="caddy"{print $1}' | xargs -r kill 2>/dev/null
sleep 1
rm -rf $ROOT/.pids

echo "==> 启动 backend (port 8080)"
cd $ROOT/backend
mkdir -p data storage/recordings storage/materials
# setsid 脱离会话 + 忽略 SIGHUP
setsid nohup ./build/server > build/server.log 2>&1 &
SPID=$!
echo "   server pid=$SPID"
disown

sleep 2
echo "==> 启动 caddy (port 8443 HTTPS + 8081 HTTP)"
cd $ROOT/docker/caddy
setsid nohup ./caddy run --config Caddyfile --adapter caddyfile > caddy.log 2>&1 &
CPID=$!
echo "   caddy  pid=$CPID"
disown

sleep 3
echo ""
echo "==> 端口监听"
ss -tlnp 2>/dev/null | grep -E ':(8080|8443|8081)'
echo ""
echo "==> 进程"
ps -eo pid,comm | awk '$2=="server"||$2=="caddy"'
echo ""
echo "==> backend 健康检查"
curl -s --connect-timeout 3 http://127.0.0.1:8080/api/v1/meetings 2>&1
echo ""
echo "==> HTTPS 健康检查 (WSL 内部)"
curl -sk --connect-timeout 3 --resolve localhost:8443:127.0.0.1 https://localhost:8443/api/v1/meetings 2>&1
echo ""
echo "✅ 启动完成，进程已脱离会话（关闭当前终端后仍存活）"
echo "   WSL IP  : $(hostname -I | awk '{print $1}')"
echo "   Windows 端口转发已就绪（netsh portproxy 0.0.0.0:8443 → 172.27.178.198:8443）"
echo ""
echo "另一台电脑访问："
echo "  https://192.168.100.101:8443"

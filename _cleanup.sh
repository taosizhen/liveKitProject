#!/bin/bash
# 清理残留进程（make up 之前跑一下）
echo "==> 清理残留进程"
pids=$(ps -eo pid,comm | awk '$2=="server"{print $1}')
if [ -n "$pids" ]; then
  echo "  kill server: $pids"
  kill $pids 2>/dev/null
  sleep 1
fi
pids=$(ps -eo pid,comm | awk '$2=="caddy"{print $1}')
if [ -n "$pids" ]; then
  echo "  kill caddy: $pids"
  kill $pids 2>/dev/null
  sleep 1
fi
rm -rf /mnt/d/CODE/WOAN/liveKitProject/.pids
sleep 1
ss -tlnp 2>/dev/null | grep -E ':(8080|8443|8081)' && echo "⚠️ 端口仍被占" || echo "✅ 端口全空"

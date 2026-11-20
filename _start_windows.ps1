# =========================================================
# Windows 原生启动 backend + caddy（彻底绕开 WSL SIGHUP）
# ---------------------------------------------------------
# 直接在 Windows 进程空间起，跟 WSL 完全隔离
# =========================================================

$ROOT      = "d:\CODE\WOAN\liveKitProject"
$BACKEND   = "$ROOT\backend"
$CADDY_BIN = "$ROOT\dev-tools\win-bin\caddy.exe"
$CADDY_CFG = "$ROOT\docker\caddy\Caddyfile"

# ---------- 1. 清理旧进程 ----------
Write-Host "==> 清理旧进程" -ForegroundColor Yellow
Get-Process server   -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process caddy    -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 800

# ---------- 2. 起 backend ----------
Write-Host "==> 启动 backend :8080" -ForegroundColor Cyan
Start-Process -FilePath "$BACKEND\server.exe" `
  -WorkingDirectory $BACKEND `
  -WindowStyle Hidden `
  -RedirectStandardOutput "$BACKEND\backend.log" `
  -RedirectStandardError "$BACKEND\backend.err.log"
Write-Host "    pid=$((Get-Process server).Id)"

# ---------- 3. 起 caddy ----------
# Caddyfile 里 root * ../../backend/web 是相对 Caddyfile 的，Windows 版一样
Write-Host "==> 启动 caddy :8443(HTTPS) + :8081(HTTP)" -ForegroundColor Cyan
Start-Process -FilePath $CADDY_BIN `
  -WorkingDirectory "$ROOT\docker\caddy" `
  -ArgumentList "run","--config",$CADDY_CFG,"--adapter","caddyfile" `
  -WindowStyle Hidden `
  -RedirectStandardOutput "$ROOT\docker\caddy\caddy-win.log" `
  -RedirectStandardError "$ROOT\docker\caddy\caddy-win.err.log"
Write-Host "    pid=$((Get-Process caddy).Id)"

Start-Sleep -Seconds 3

# ---------- 4. 验证 ----------
Write-Host ""
Write-Host "==> 验证端口监听" -ForegroundColor Yellow
netstat -ano | Select-String "LISTENING" | Select-String ":(8080|8443|8081)"

Write-Host ""
Write-Host "==> backend HTTP test" -ForegroundColor Yellow
try {
  $r = curl.exe -s --connect-timeout 3 http://127.0.0.1:8080/api/v1/meetings 2>&1
  Write-Host "    $r"
} catch { Write-Host "    ❶ 失败" }

Write-Host ""
Write-Host "==> caddy HTTP :8081 test" -ForegroundColor Yellow
try {
  $r = curl.exe -s --connect-timeout 3 http://127.0.0.1:8081/api/v1/meetings 2>&1
  Write-Host "    $r"
} catch { Write-Host "    ❶ 失败" }

Write-Host ""
Write-Host "==> 局域网 IP 测试" -ForegroundColor Yellow
try {
  $r = curl.exe -s --connect-timeout 3 http://192.168.100.101:8081/api/v1/meetings 2>&1
  Write-Host "    $r"
} catch { Write-Host "    ❶ 失败" }

Write-Host ""
Write-Host "✅ 启动完成（进程在 Windows 原生空间，关闭当前终端仍存活）" -ForegroundColor Green
Write-Host "   backend :  $BACKEND\backend.log"
Write-Host "   caddy   :  $ROOT\docker\caddy\caddy-win.log"
Write-Host ""
Write-Host "访问："
Write-Host "  HTTPS: https://192.168.100.101:8443  (浏览器提示不安全→点高级→继续)"
Write-Host "  HTTP : http://192.168.100.101:8081   (自动跳 HTTPS)"
Write-Host ""
Write-Host "关闭：taskkill /F /IM server.exe; taskkill /F /IM caddy.exe" -ForegroundColor Gray

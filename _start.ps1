# =========================================================
# Windows 原生启动（彻底绕开 WSL SIGHUP + 下载依赖）
# ---------------------------------------------------------
# 方案：mkcert 已自签证书 → Vite dev server 原生 HTTPS
#        backend/server.exe Windows 原生进程
# 两个进程都在 Windows 进程空间，永不被杀
# =========================================================

$ROOT    = "d:\CODE\WOAN\liveKitProject"
$BACKEND = "$ROOT\backend"
$FRONT   = "$ROOT\frontend"
$CERTS   = "$ROOT\dev-tools\certs"

$ports   = @(5173, 8080)

Write-Host "==> 清理旧进程 + 释放端口 $($ports -join ', ')" -ForegroundColor Yellow
Get-Process server -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process node  -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*vite*" } | Stop-Process -Force
Start-Sleep -Milliseconds 800

# ---------- 1. 起 backend（Windows 原生 server.exe）----------
Write-Host "==> 起 backend :8080  [Windows 原生]" -ForegroundColor Cyan
$backProc = Start-Process -FilePath "$BACKEND\server.exe" `
  -WorkingDirectory $BACKEND -WindowStyle Hidden -PassThru
Write-Host "    pid=$($backProc.Id)"

Start-Sleep -Seconds 3

# ---------- 2. 起 Vite dev server（mkcert 证书 → HTTPS :5173）----------
# vite.config.ts 已配好 mkcert 证书自动加载
# 在 frontend/ 下 npm run dev
Write-Host "==> 起 Vite dev HTTPS :5173  [mkcert 证书]" -ForegroundColor Cyan
$npmCmd = "npm.cmd"
if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
  $npmCmd = "$env:APPDATA\npm\npm.cmd"
}
$viteProc = Start-Process -FilePath $npmCmd `
  -WorkingDirectory $FRONT -ArgumentList "run","dev" `
  -WindowStyle Hidden -PassThru
Write-Host "    pid=$($viteProc.Id)"

Start-Sleep -Seconds 6

# ---------- 3. 验证 ----------
Write-Host ""
Write-Host "==> Windows 本机端口监听" -ForegroundColor Yellow
netstat -ano | Select-String "LISTENING" | Select-String -Pattern ":(5173|8080)"

Write-Host ""
Write-Host "==> backend 测试" -ForegroundColor Yellow
curl.exe -s --connect-timeout 3 http://127.0.0.1:8080/api/v1/meetings 2>&1

Write-Host ""
Write-Host "==> Vite dev HTTP 测试" -ForegroundColor Yellow
curl.exe -sk --connect-timeout 3 https://localhost:5173/api/v1/meetings 2>&1

Write-Host ""
Write-Host "✅ 启动完成！" -ForegroundColor Green
Write-Host ""
Write-Host "  前端 HTTPS dev : https://localhost:5173   (mkcert 证书)"
Write-Host "  backend API   :   http://localhost:8080"
Write-Host ""
Write-Host "  ⚠️ 另一台电脑访问："
Write-Host "     浏览器打开  https://192.168.100.101:5173"
Write-Host "     提示『不安全』→ 高级 → 继续前往"
Write-Host "     （5173 已配置 host:0.0.0.0，局域网机器能直接连）"
Write-Host ""
Write-Host "  关闭：taskkill /F /IM server.exe; taskkill /F /IM node.exe" -ForegroundColor Gray

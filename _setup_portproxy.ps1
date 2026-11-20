# 取 WSL 虚拟网卡 IP
$wslOut = wsl -e bash -c "hostname -I"
$wslIp  = ($wslOut -split '\s+')[0]
Write-Host "WSL_IP = $wslIp" -ForegroundColor Cyan

if (-not $wslIp) { Write-Host "❌ 取 WSL IP 失败" -ForegroundColor Red; exit 1 }

# 1. 清旧规则
foreach ($p in @(8443, 8081, 8080, 7880, 7882)) {
    netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$p 2>$null | Out-Null
}

# 2. 加新规则
foreach ($p in @(8443, 8081, 8080, 7880, 7882)) {
    netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$p connectaddress=$wslIp connectport=$p
}

Write-Host ""
Write-Host "=== 当前 portproxy 规则 ===" -ForegroundColor Yellow
netsh interface portproxy show all

# 3. Windows 防火墙放行
Write-Host ""
Write-Host "=== 防火墙放行 ===" -ForegroundColor Yellow
foreach ($p in @(8443, 8081, 8080, 7880, 7882)) {
    netsh advfirewall firewall add rule name="MeetingPlatform-$p" dir=in action=allow protocol=TCP localport=$p 2>$null | Out-Null
    Write-Host "  ✅ TCP $p"
}

Write-Host ""
Write-Host "=== Windows 侧本机测试 ===" -ForegroundColor Yellow
curl.exe -sk --connect-timeout 3 https://127.0.0.1:8443/api/v1/health 2>&1
Write-Host ""
curl.exe -sk --connect-timeout 3 http://127.0.0.1:8081/api/v1/health 2>&1
Write-Host ""
Write-Host "=== 局域网 IP 测试 ===" -ForegroundColor Yellow
curl.exe -sk --connect-timeout 3 https://192.168.100.101:8443/api/v1/health 2>&1

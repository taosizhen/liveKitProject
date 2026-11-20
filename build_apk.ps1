# 构建 Flutter Android APK（开发机无 Go 无关；仅需 Node/Flutter/JDK 已就绪）
#
# 用法：
#   .\build_apk.ps1                 # 通用 release APK（体积较大，兼容所有 ABI）
#   .\build_apk.ps1 -Split          # 按 ABI 拆分，产物更小（推荐真机分发）
#   .\build_apk.ps1 -Clean          # 先 flutter clean 再构建
#   .\build_apk.ps1 -Debug          # 构建 debug 包（便于排查）
#
# 说明：
# 1. 统一使用仓库内 .toolchain 的 Flutter 与 pub 缓存，避免污染全局环境；
# 2. 将 KOTLIN_USER_HOME 指向项目内，避免 Kotlin 向 %LOCALAPPDATA%\kotlin 写入
#    （受限沙箱环境会拦截该路径，导致构建失败）；
# 3. release 包当前使用 debug 签名，仅用于内测安装，上架前需配置正式 keystore。
param(
    [switch]$Split,
    [switch]$Clean,
    [switch]$Debug
)

$ErrorActionPreference = 'Stop'

# 项目根目录（脚本所在目录）
$Root = $PSScriptRoot
$MobileDir = Join-Path $Root 'meeting_mobile'
$Flutter = Join-Path $Root '.toolchain\flutter\bin\flutter.bat'
$OutputDir = Join-Path $Root 'dist\apk'

# 构建环境：工具链与缓存全部收敛到仓库内
$env:PUB_CACHE = Join-Path $Root '.toolchain\pub-cache'
$env:KOTLIN_USER_HOME = Join-Path $Root '.kotlin-home'
New-Item -ItemType Directory -Force $env:KOTLIN_USER_HOME | Out-Null

if (-not (Test-Path $Flutter)) {
    throw "未找到 Flutter SDK：$Flutter（请确认 .toolchain 目录完整）"
}

Write-Host "==> Flutter: $Flutter" -ForegroundColor Cyan
Write-Host "==> PUB_CACHE: $env:PUB_CACHE" -ForegroundColor Cyan
Write-Host "==> KOTLIN_USER_HOME: $env:KOTLIN_USER_HOME" -ForegroundColor Cyan

Push-Location $MobileDir
try {
    if ($Clean) {
        Write-Host '==> flutter clean' -ForegroundColor Yellow
        & $Flutter clean
    }

    Write-Host '==> flutter pub get' -ForegroundColor Yellow
    & $Flutter pub get

    # 组装构建参数
    $buildArgs = @('build', 'apk')
    if ($Debug) {
        $buildArgs += '--debug'
    }
    else {
        $buildArgs += '--release'
        if ($Split) { $buildArgs += '--split-per-abi' }
    }

    Write-Host "==> flutter $($buildArgs -join ' ')" -ForegroundColor Yellow
    # 记录构建开始时间：只收集本次生成的 APK，避免把历史产物当成本次结果
    $buildStart = Get-Date
    & $Flutter @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "构建失败，退出码 $LASTEXITCODE"
    }

    # 收集产物到 dist/apk（带构建时间戳，便于区分版本）
    $apkDir = Join-Path $MobileDir 'build\app\outputs\flutter-apk'
    $apks = Get-ChildItem $apkDir -Filter '*.apk' -ErrorAction SilentlyContinue | Where-Object {
        $_.LastWriteTime -ge $buildStart -and $(
            if ($Debug) { $_.Name -like '*debug*' } else { $_.Name -like '*release*' }
        )
    }
    if (-not $apks) { throw "未找到 APK 产物：$apkDir" }

    New-Item -ItemType Directory -Force $OutputDir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmm'
    foreach ($apk in $apks) {
        $dest = Join-Path $OutputDir ($apk.BaseName + "-$stamp" + $apk.Extension)
        Copy-Item $apk.FullName $dest -Force
        Write-Host ("==> 产物：{0}  ({1:N1} MB)" -f $dest, ($apk.Length / 1MB)) -ForegroundColor Green
    }

    Write-Host '==> 安装：adb install -r <上面的 apk>' -ForegroundColor Cyan
    Write-Host '==> 提示：App 连接的后端地址在 meeting_mobile/assets/config.json 中配置' -ForegroundColor Cyan
}
finally {
    Pop-Location
}

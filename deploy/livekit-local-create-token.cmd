@echo off
REM LiveKit Docker 容器内生成密钥对脚本
REM 在项目根目录运行: .\deploy\livekit-local-create-token.cmd

docker run --rm livekit/livekit:latest create-keys --export
echo.
echo 上面输出的 keys: API Key 和 Secret Key 填入 deploy\livekit.yaml 的 keys 段
pause

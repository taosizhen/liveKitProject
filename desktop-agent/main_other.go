//go:build !windows

// 非 Windows 平台的占位实现：
// 远程控制代理依赖 user32/shcore（仅 Windows 存在），
// 该文件保证在 Linux/macOS（含 WSL）下 `go build ./...` 仍可编译通过，
// 实际能力只在 Windows 上可用。
package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Fprintln(os.Stderr, "远程控制桌面代理仅支持 Windows，请在 Windows 上运行（或在 WSL 中交叉编译）：")
	fmt.Fprintln(os.Stderr, "  GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -o desktop-agent.exe .")
	os.Exit(1)
}

//go:build windows

// 远程控制桌面代理（被控端 PC 本地运行）
//
// 安全模型：
// - 仅监听 127.0.0.1:17653（回环地址，不接受外部连接）
// - 浏览器先 POST /session 创建一次性会话 token（30 秒有效、全局单会话）
// - GET /control?token= 升级 WebSocket 时校验并消费 token（最后硬门槛，防伪造）
// - Ctrl+Alt+Esc 全局快捷键可随时强制结束会话
//
// 输入注入：归一化坐标 [0..1] → SendInput（MOUSEEVENTF_ABSOLUTE 0..65535）。
// 说明：未使用 robotgo（依赖 CGO，无法在 WSL 中交叉编译 Windows 可执行文件），
// 改用 golang.org/x/sys/windows 直接调用 user32 SendInput，纯 Go 即可交叉编译
// （WSL 中：GOOS=windows CGO_ENABLED=0 go build）。
// DPI 感知：启动时调用 shcore.SetProcessDpiAwareness(2)，避免缩放下坐标偏移。
package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"log"
	"net/http"
	"runtime"
	"sync"
	"time"
	"unsafe"

	"github.com/gorilla/websocket"
	"golang.org/x/sys/windows"
)

const listenAddr = "127.0.0.1:17653"

var (
	user32 = windows.NewLazySystemDLL("user32.dll")
	shcore = windows.NewLazySystemDLL("shcore.dll")

	procSendInput                = user32.NewProc("SendInput")
	procRegisterHotKey           = user32.NewProc("RegisterHotKey")
	procUnregisterHotKey         = user32.NewProc("UnregisterHotKey")
	procGetMessageW              = user32.NewProc("GetMessageW")
	procSetProcessDpiAwareness   = shcore.NewProc("SetProcessDpiAwareness")
)

// ---------- Win32 输入结构（x64 布局，INPUT 固定 40 字节） ----------

const (
	inMouse    = 0
	inKeyboard = 1

	mouseeventfMove      = 0x0001
	mouseeventfLeftDown  = 0x0002
	mouseeventfLeftUp    = 0x0004
	mouseeventfRightDown = 0x0008
	mouseeventfRightUp   = 0x0010
	mouseeventfMiddleDown = 0x0020
	mouseeventfMiddleUp  = 0x0040
	mouseeventfWheel     = 0x0800
	mouseeventfAbsolute  = 0x8000

	keyeventfKeyUp = 0x0002
)

type mouseInput struct {
	dx        int32
	dy        int32
	mouseData uint32
	flags     uint32
	time      uint32
	extraInfo uintptr
}

type inputMouse struct {
	typ uint32
	pad uint32
	mi  mouseInput
}

type keybdInput struct {
	wVk       uint16
	wScan     uint16
	flags     uint32
	time      uint32
	extraInfo uintptr
}

type inputKey struct {
	typ  uint32
	pad  uint32
	ki   keybdInput
	pad2 [8]byte // 补齐到 mouseInput 的 32 字节（union 取最大成员）
}

/** 向系统注入一次鼠标事件（SendInput 封装） */
func sendMouse(in mouseInput) {
	i := inputMouse{typ: inMouse, mi: in}
	procSendInput.Call(1, uintptr(unsafe.Pointer(&i)), unsafe.Sizeof(i))
}

/** 向系统注入一次按键（vk 虚拟键码，up=true 表示抬起） */
func sendKey(vk uint16, up bool) {
	var flags uint32
	if up {
		flags = keyeventfKeyUp
	}
	i := inputKey{typ: inKeyboard, ki: keybdInput{wVk: vk, flags: flags}}
	procSendInput.Call(1, uintptr(unsafe.Pointer(&i)), unsafe.Sizeof(i))
}

/** 归一化坐标移动鼠标（绝对模式 0..65535 映射主屏物理像素） */
func moveTo(x, y float64) {
	clamp := func(v float64) float64 {
		if v < 0 {
			return 0
		}
		if v > 1 {
			return 1
		}
		return v
	}
	sendMouse(mouseInput{
		dx:    int32(clamp(x) * 65535),
		dy:    int32(clamp(y) * 65535),
		flags: mouseeventfMove | mouseeventfAbsolute,
	})
}

/** 鼠标按下/抬起（先移动到目标点再点击） */
func clickButton(x, y float64, button string, up bool) {
	moveTo(x, y)
	var flag uint32
	switch button {
	case "right":
		if up {
			flag = mouseeventfRightUp
		} else {
			flag = mouseeventfRightDown
		}
	case "middle":
		if up {
			flag = mouseeventfMiddleUp
		} else {
			flag = mouseeventfMiddleDown
		}
	default: // left
		if up {
			flag = mouseeventfLeftUp
		} else {
			flag = mouseeventfLeftDown
		}
	}
	sendMouse(mouseInput{flags: flag})
}

/** 滚轮（浏览器 deltaY 向下为正，Windows 向上为正，取反并换算为 WHEEL_DELTA=120 的倍数） */
func wheel(dy float64) {
	clicks := dy / 100
	data := int32(-clicks * 120)
	if data == 0 && dy != 0 {
		if dy > 0 {
			data = -120
		} else {
			data = 120
		}
	}
	sendMouse(mouseInput{mouseData: uint32(data), flags: mouseeventfWheel})
}

/** JS KeyboardEvent.key → Windows 虚拟键码 */
func mapKey(key string) uint16 {
	// 单字符：字母/数字直接取大写 ASCII（与 VK 一致）
	if len(key) == 1 {
		c := key[0]
		switch {
		case c >= 'a' && c <= 'z':
			return uint16(c - 'a' + 'A')
		case c >= 'A' && c <= 'Z':
			return uint16(c)
		case c >= '0' && c <= '9':
			return uint16(c)
		}
		// 常见符号（OEM 键码，美式布局）
		switch c {
		case ' ':
			return 0x20
		case '-':
			return 0xBD
		case '=':
			return 0xBB
		case ',':
			return 0xBC
		case '.':
			return 0xBE
		case '/':
			return 0xBF
		case ';':
			return 0xBA
		case '\'':
			return 0xDE
		case '[':
			return 0xDB
		case ']':
			return 0xDD
		case '\\':
			return 0xDC
		case '`':
			return 0xC0
		}
		return 0
	}
	if len(key) >= 2 && key[0] == 'F' { // F1..F12
		var n int
		for _, c := range key[1:] {
			if c < '0' || c > '9' {
				return 0
			}
			n = n*10 + int(c-'0')
		}
		if n >= 1 && n <= 12 {
			return uint16(0x70 + n - 1)
		}
		return 0
	}
	switch key {
	case "Enter":
		return 0x0D
	case "Escape":
		return 0x1B
	case "Tab":
		return 0x09
	case "Backspace":
		return 0x08
	case "Delete":
		return 0x2E
	case "Insert":
		return 0x2D
	case "Home":
		return 0x24
	case "End":
		return 0x23
	case "PageUp":
		return 0x21
	case "PageDown":
		return 0x22
	case "ArrowLeft":
		return 0x25
	case "ArrowUp":
		return 0x26
	case "ArrowRight":
		return 0x27
	case "ArrowDown":
		return 0x28
	case "Control":
		return 0x11
	case "Shift":
		return 0x10
	case "Alt":
		return 0x12
	case "Meta":
		return 0x5B // 左 Win
	case "CapsLock":
		return 0x14
	}
	return 0
}

// ---------- 输入消息 ----------

type inputMsg struct {
	Type   string  `json:"type"` // move | down | up | wheel | key
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Button string  `json:"button"`
	DeltaY float64 `json:"dy"`
	Key    string  `json:"key"`
	Down   bool    `json:"down"`
}

/** 分发一条输入事件到 OS */
func dispatch(m inputMsg) {
	switch m.Type {
	case "move":
		moveTo(m.X, m.Y)
	case "down":
		clickButton(m.X, m.Y, m.Button, false)
	case "up":
		clickButton(m.X, m.Y, m.Button, true)
	case "wheel":
		wheel(m.DeltaY)
	case "key":
		if vk := mapKey(m.Key); vk != 0 {
			sendKey(vk, !m.Down)
		}
	}
}

// ---------- 会话管理（全局单会话 + 一次性 token） ----------

type session struct {
	token   string
	expires time.Time
	active  bool
	conn    *websocket.Conn
}

var (
	sessMu      sync.Mutex
	cur         *session
)

/** 创建一次性会话 token（已有活跃会话时返回 false） */
func newSession() (string, bool) {
	sessMu.Lock()
	defer sessMu.Unlock()
	if cur != nil && (cur.active || time.Now().Before(cur.expires)) {
		return "", false
	}
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return "", false
	}
	token := hex.EncodeToString(buf)
	cur = &session{token: token, expires: time.Now().Add(30 * time.Second)}
	log.Printf("[agent] 会话已创建，等待浏览器建立 WebSocket（30s 内有效）")
	return token, true
}

/** 校验并消费 token，激活会话（WS 握手时调用，幂等拒绝重放） */
func activateSession(token string, conn *websocket.Conn) bool {
	sessMu.Lock()
	defer sessMu.Unlock()
	if cur == nil || cur.active || cur.token != token || time.Now().After(cur.expires) {
		return false
	}
	cur.active = true
	cur.conn = conn
	return true
}

/** 结束当前会话（WS 断开 / Ctrl+Alt+Esc / 新会话顶替） */
func endSession(reason string) {
	sessMu.Lock()
	s := cur
	cur = nil
	sessMu.Unlock()
	if s != nil && s.conn != nil {
		_ = s.conn.Close()
	}
	if s != nil {
		log.Printf("[agent] 会话已结束：%s", reason)
	}
}

/** 当前是否有活跃会话 */
func sessionBusy() bool {
	sessMu.Lock()
	defer sessMu.Unlock()
	return cur != nil && (cur.active || time.Now().Before(cur.expires))
}

// ---------- HTTP / WebSocket ----------

var upgrader = websocket.Upgrader{
	// 浏览器页面与回环代理必为跨源，安全由一次性 token 保证
	CheckOrigin: func(r *http.Request) bool { return true },
}

/** 统一写 JSON 响应（带宽松 CORS，供会议页跨源探测） */
func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

/** GET /status：连通性探测（浏览器判断代理是否在运行） */
func handleStatus(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "busy": sessionBusy()})
}

/** POST /session：创建一次性会话 token */
func handleSession(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"ok": false})
		return
	}
	token, ok := newSession()
	if !ok {
		writeJSON(w, http.StatusConflict, map[string]any{"ok": false, "error": "busy"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "token": token})
}

/** GET /control?token=：校验 token 后升级 WebSocket，进入输入注入循环 */
func handleControl(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	if !activateSession(token, conn) {
		_ = conn.WriteJSON(map[string]any{"type": "error", "error": "invalid_token"})
		_ = conn.Close()
		return
	}
	log.Printf("[agent] 远程控制会话开始（Ctrl+Alt+Esc 强制结束）")
	_ = conn.WriteJSON(map[string]any{"type": "ready"})

	for {
		var m inputMsg
		if err := conn.ReadJSON(&m); err != nil {
			break
		}
		dispatch(m)
	}
	endSession("websocket 断开")
}

/** 全局快捷键监听：Ctrl+Alt+Esc 强制结束会话（需独立 OS 线程跑消息循环） */
func hotkeyLoop() {
	runtime.LockOSThread()
	const (
		modAlt     = 0x0001
		modControl = 0x0002
		vkEscape   = 0x1B
		wmHotkey   = 0x0312
	)
	r, _, err := procRegisterHotKey.Call(0, 1, modControl|modAlt, vkEscape)
	if r == 0 {
		log.Printf("[agent] 注册 Ctrl+Alt+Esc 失败：%v（仍可正常控制）", err)
		return
	}
	type point struct{ X, Y int32 }
	type msg struct {
		Hwnd    uintptr
		Message uint32
		WParam  uintptr
		LParam  uintptr
		Time    uint32
		Pt      point
	}
	var m msg
	for {
		r, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0)
		if r == 0 { // WM_QUIT
			return
		}
		if m.Message == wmHotkey {
			log.Printf("[agent] 收到 Ctrl+Alt+Esc，强制结束会话")
			endSession("快捷键终止")
		}
	}
}

func main() {
	// DPI 感知（PROCESS_PER_MONITOR_DPI_AWARE=2），避免缩放下坐标偏移
	_, _, _ = procSetProcessDpiAwareness.Call(2)

	go hotkeyLoop()

	mux := http.NewServeMux()
	mux.HandleFunc("/status", handleStatus)
	mux.HandleFunc("/session", handleSession)
	mux.HandleFunc("/control", handleControl)
	// 预检请求统一放行
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodOptions {
			writeJSON(w, http.StatusOK, map[string]any{"ok": true})
			return
		}
		writeJSON(w, http.StatusNotFound, map[string]any{"ok": false})
	})

	log.Printf("[agent] 远程控制代理已启动：http://%s（仅回环）", listenAddr)
	log.Printf("[agent] 安全提示：会话需一次性 token；Ctrl+Alt+Esc 可随时强制结束")
	if err := http.ListenAndServe(listenAddr, mux); err != nil {
		log.Fatalf("[agent] 启动失败：%v", err)
	}
}

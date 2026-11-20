// 远程控制层（topic=`remote_control`，reliable）
// - 控制端（仅动态主持人可发起）：请求控制 → 捕获键鼠（归一化 0..1，扣除 contain 黑边）→ 广播 rc_input
// - 被控端（须正在共享屏幕）：弹授权窗 → 允许后连本地代理（ws://127.0.0.1:17653）→ 转发 rc_input 给代理注入 OS
// - 任一端可 rc_end；心跳 5s，15s 无消息超时自动结束；停止共享自动结束
import { useCallback, useEffect, useRef } from 'react';
import type { Room } from 'livekit-client';
import { MonitorUp, XCircle } from 'lucide-react';
import { publishDataMessage, useDataChannel } from '@/hooks/useDataChannel';
import { checkAgent, connectAgent, createSession } from '@/services/remoteControlAgent';
import { useRemoteControlStore } from '@/store/remoteControlStore';

const RC_TOPIC = 'remote_control';

interface RemoteControlLayerProps {
  room: Room;
  /** 当前是否为动态主持人（仅主持人可发起远程控制） */
  isHost: boolean;
  localIdentity: string;
  localName: string;
  /** 屏幕共享者 identity（无共享时为 null） */
  screenShareIdentity: string | null;
  /** 是否本端在共享屏幕 */
  screenShareIsLocal: boolean;
  /** 主舞台视频元素（用于 contain 黑边扣除的坐标归一化） */
  getVideoEl: () => HTMLVideoElement | null;
  /** 标注中不渲染控制层 */
  annotating: boolean;
}

/** 远程控制层：授权弹窗 / 请求按钮 / 控制捕获层 / 状态条 */
export default function RemoteControlLayer({
  room,
  isHost,
  localIdentity,
  localName,
  screenShareIdentity,
  screenShareIsLocal,
  getVideoEl,
  annotating,
}: RemoteControlLayerProps) {
  const role = useRemoteControlStore((s) => s.role);
  const peerIdentity = useRemoteControlStore((s) => s.peerIdentity);
  const peerName = useRemoteControlStore((s) => s.peerName);
  const incomingRequest = useRemoteControlStore((s) => s.incomingRequest);
  const notice = useRemoteControlStore((s) => s.notice);
  const agentMissing = useRemoteControlStore((s) => s.agentMissing);

  const agentWsRef = useRef<WebSocket | null>(null); // 被控端：本地代理连接
  const lastMsgAtRef = useRef(0); // 被控端：最近一次收到控制消息的时间
  const pingTimerRef = useRef(0); // 控制端：心跳定时器
  const watchdogRef = useRef(0); // 被控端：超时看门狗
  const overlayRef = useRef<HTMLDivElement>(null);

  /** 广播远程控制信令 */
  const post = useCallback(
    (msg: Record<string, unknown>) =>
      publishDataMessage(room, RC_TOPIC, { src: 'remote_control', ts: Date.now(), ...msg }),
    [room],
  );

  /** 结束会话（双向）：发 rc_end + 断代理 + 清定时器 + 复位 */
  const endSession = useCallback(
    (silent = false) => {
      const st = useRemoteControlStore.getState();
      if (st.role !== 'none' && st.peerIdentity) {
        post({ k: 'rc_end', from: localIdentity, to: st.peerIdentity });
      }
      agentWsRef.current?.close();
      agentWsRef.current = null;
      window.clearInterval(pingTimerRef.current);
      window.clearInterval(watchdogRef.current);
      useRemoteControlStore.getState().reset();
      if (!silent) useRemoteControlStore.getState().setNotice('远程控制已结束');
      window.setTimeout(() => useRemoteControlStore.getState().setNotice(null), 3000);
    },
    [post, localIdentity],
  );

  // —— 信令处理 ——
  const handleMessage = useCallback(
    (msg: Record<string, unknown>) => {
      if (msg.src !== 'remote_control') return;
      const st = useRemoteControlStore.getState();
      const set = useRemoteControlStore.setState;
      const to = String(msg.to ?? '');
      const from = String(msg.from ?? '');
      const k = String(msg.k ?? '');

      // 被控端：任何发往自己的控制消息都刷新看门狗
      if (to === localIdentity && (k === 'rc_input' || k === 'rc_ping')) {
        lastMsgAtRef.current = Date.now();
      }

      switch (k) {
        case 'rc_request': {
          // 仅当自己是共享者且空闲时弹授权窗
          if (String(msg.target ?? '') !== localIdentity) return;
          if (st.role !== 'none') return;
          set({ incomingRequest: { from, name: String(msg.name ?? from) } });
          break;
        }
        case 'rc_accept': {
          if (to !== localIdentity || st.role !== 'requesting') return;
          set({ role: 'controller' });
          set({ notice: `已开始控制「${st.peerName ?? from}」的屏幕` });
          window.setTimeout(() => useRemoteControlStore.getState().setNotice(null), 3000);
          // 控制端心跳
          window.clearInterval(pingTimerRef.current);
          pingTimerRef.current = window.setInterval(() => {
            post({ k: 'rc_ping', from: localIdentity, to });
          }, 5000);
          break;
        }
        case 'rc_reject': {
          if (to !== localIdentity || st.role !== 'requesting') return;
          const reason = msg.reason === 'no_agent' ? '对方未运行远程控制代理' : '对方拒绝了控制请求';
          set({ notice: reason });
          window.setTimeout(() => useRemoteControlStore.getState().setNotice(null), 4000);
          useRemoteControlStore.getState().reset();
          break;
        }
        case 'rc_end': {
          if (to !== localIdentity || st.role === 'none') return;
          agentWsRef.current?.close();
          agentWsRef.current = null;
          window.clearInterval(pingTimerRef.current);
          window.clearInterval(watchdogRef.current);
          set({ notice: '远程控制已结束' });
          window.setTimeout(() => useRemoteControlStore.getState().setNotice(null), 3000);
          useRemoteControlStore.getState().reset();
          break;
        }
        case 'rc_input': {
          // 被控端：转发给本地代理注入 OS
          if (to !== localIdentity || st.role !== 'controlled') return;
          const ws = agentWsRef.current;
          if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({
              type: msg.type, x: msg.x, y: msg.y,
              button: msg.button, dy: msg.dy, key: msg.key, down: msg.down,
            }));
          }
          break;
        }
        default:
          break;
      }
    },
    [localIdentity, post],
  );

  useDataChannel(room, RC_TOPIC, handleMessage);

  // —— 控制端：发起请求 ——

  /** 请求控制共享者（仅主持人、他人在共享、空闲时可用） */
  const requestControl = useCallback(() => {
    if (!isHost || !screenShareIdentity || screenShareIsLocal) return;
    if (useRemoteControlStore.getState().role !== 'none') return;
    post({ k: 'rc_request', target: screenShareIdentity, from: localIdentity, name: localName });
    useRemoteControlStore.getState().setRole('requesting', {
      identity: screenShareIdentity,
      name: participants_nameOf(screenShareIdentity),
    });
  }, [isHost, screenShareIdentity, screenShareIsLocal, post, localIdentity, localName]);

  /** 由 identity 查显示名（通过房间 participants） */
  function participants_nameOf(identity: string): string {
    const p = room.remoteParticipants.get(identity);
    return p?.name || identity;
  }

  // —— 被控端：授权处理 ——

  /** 允许控制：检代理 → 建会话 → 连 WS → 回 rc_accept → 进入被控态 */
  const acceptControl = useCallback(async () => {
    const req = useRemoteControlStore.getState().incomingRequest;
    if (!req) return;
    const set = useRemoteControlStore.setState;
    set({ incomingRequest: null });

    const alive = await checkAgent();
    if (!alive) {
      // 代理未运行：回 no_agent 并引导下载
      post({ k: 'rc_reject', from: localIdentity, to: req.from, reason: 'no_agent' });
      set({ agentMissing: true });
      return;
    }
    try {
      const token = await createSession();
      const ws = await connectAgent(token);
      agentWsRef.current = ws;
      ws.onclose = () => {
        // 代理侧断开（含 Ctrl+Alt+Esc 强杀）→ 结束会话
        if (useRemoteControlStore.getState().role === 'controlled') {
          endSession();
        }
      };
      post({ k: 'rc_accept', from: localIdentity, to: req.from, agentReady: true });
      useRemoteControlStore.getState().setRole('controlled', { identity: req.from, name: req.name });
      lastMsgAtRef.current = Date.now();
      // 看门狗：15s 无任何控制消息则自动结束
      window.clearInterval(watchdogRef.current);
      watchdogRef.current = window.setInterval(() => {
        if (Date.now() - lastMsgAtRef.current > 15000) endSession();
      }, 5000);
    } catch (e) {
      post({ k: 'rc_reject', from: localIdentity, to: req.from, reason: 'no_agent' });
      set({ notice: (e as Error).message });
      window.setTimeout(() => useRemoteControlStore.getState().setNotice(null), 4000);
    }
  }, [post, localIdentity, endSession]);

  /** 拒绝控制 */
  const rejectControl = useCallback(() => {
    const req = useRemoteControlStore.getState().incomingRequest;
    if (!req) return;
    useRemoteControlStore.setState({ incomingRequest: null });
    post({ k: 'rc_reject', from: localIdentity, to: req.from, reason: 'declined' });
  }, [post, localIdentity]);

  // 停止共享 / 对端下线 → 自动结束
  useEffect(() => {
    if (role === 'controlled' && !screenShareIsLocal) endSession();
    if (role === 'controller' && screenShareIdentity !== peerIdentity) endSession();
  }, [role, screenShareIsLocal, screenShareIdentity, peerIdentity, endSession]);

  // 卸载清理
  useEffect(() => {
    return () => {
      agentWsRef.current?.close();
      window.clearInterval(pingTimerRef.current);
      window.clearInterval(watchdogRef.current);
    };
  }, []);

  // —— 控制端：事件捕获（归一化坐标，扣除 object-fit:contain 黑边） ——

  /** 把页面坐标换算为共享画面内的归一化坐标 [0..1] */
  const normalize = useCallback(
    (clientX: number, clientY: number): { x: number; y: number } | null => {
      const el = getVideoEl();
      if (!el || !el.videoWidth || !el.videoHeight) return null;
      const rect = el.getBoundingClientRect();
      const scale = Math.min(rect.width / el.videoWidth, rect.height / el.videoHeight);
      const dispW = el.videoWidth * scale;
      const dispH = el.videoHeight * scale;
      const offX = rect.left + (rect.width - dispW) / 2;
      const offY = rect.top + (rect.height - dispH) / 2;
      const x = (clientX - offX) / dispW;
      const y = (clientY - offY) / dispH;
      if (x < 0 || x > 1 || y < 0 || y > 1) return null; // 黑边区域忽略
      return { x, y };
    },
    [getVideoEl],
  );

  /** 发送一条输入事件 */
  const sendInput = useCallback(
    (msg: Record<string, unknown>) => {
      const peer = useRemoteControlStore.getState().peerIdentity;
      if (!peer) return;
      post({ k: 'rc_input', from: localIdentity, to: peer, ...msg });
    },
    [post, localIdentity],
  );

  // move 节流 ~30ms（rAF 驱动）
  const pendingMoveRef = useRef<{ x: number; y: number } | null>(null);
  const moveScheduledRef = useRef(false);
  /** 节流发送鼠标移动 */
  const sendMove = useCallback(
    (x: number, y: number) => {
      pendingMoveRef.current = { x, y };
      if (moveScheduledRef.current) return;
      moveScheduledRef.current = true;
      window.setTimeout(() => {
        moveScheduledRef.current = false;
        const m = pendingMoveRef.current;
        if (m) sendInput({ type: 'move', x: m.x, y: m.y });
      }, 30);
    },
    [sendInput],
  );

  const buttonName = (b: number) => (b === 2 ? 'right' : b === 1 ? 'middle' : 'left');

  if (annotating) return null;

  return (
    <>
      {/* 控制端：捕获层（接管舞台键鼠） */}
      {role === 'controller' && (
        <div
          ref={overlayRef}
          tabIndex={-1}
          onContextMenu={(e) => e.preventDefault()}
          onPointerMove={(e) => {
            const p = normalize(e.clientX, e.clientY);
            if (p) sendMove(p.x, p.y);
          }}
          onPointerDown={(e) => {
            overlayRef.current?.setPointerCapture(e.pointerId);
            overlayRef.current?.focus();
            const p = normalize(e.clientX, e.clientY);
            if (p) sendInput({ type: 'down', x: p.x, y: p.y, button: buttonName(e.button) });
          }}
          onPointerUp={(e) => {
            const p = normalize(e.clientX, e.clientY);
            if (p) sendInput({ type: 'up', x: p.x, y: p.y, button: buttonName(e.button) });
          }}
          onWheel={(e) => {
            sendInput({ type: 'wheel', dy: e.deltaY });
          }}
          onKeyDown={(e) => {
            e.preventDefault();
            sendInput({ type: 'key', key: e.key, down: true });
          }}
          onKeyUp={(e) => {
            e.preventDefault();
            sendInput({ type: 'key', key: e.key, down: false });
          }}
          className="absolute inset-0 z-10 cursor-crosshair outline-none"
        />
      )}

      {/* 请求控制按钮（主持人 + 他人在共享 + 空闲） */}
      {role === 'none' && isHost && screenShareIdentity && !screenShareIsLocal && (
        <button
          type="button"
          onClick={requestControl}
          className="absolute bottom-3 left-1/2 -translate-x-1/2 z-20 flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-brand-600/90 hover:bg-brand-600 text-white text-xs shadow-lg"
        >
          <MonitorUp className="w-3.5 h-3.5" />请求远程控制
        </button>
      )}

      {/* 请求中提示 */}
      {role === 'requesting' && (
        <div className="absolute bottom-3 left-1/2 -translate-x-1/2 z-20 flex items-center gap-2 px-3 py-1.5 rounded-full bg-slate-800/90 text-white text-xs shadow-lg">
          等待「{peerName}」授权…
          <button type="button" onClick={() => endSession(true)} className="text-white/60 hover:text-white">
            取消
          </button>
        </div>
      )}

      {/* 控制中 / 被控中状态条 */}
      {(role === 'controller' || role === 'controlled') && (
        <div className="absolute top-3 right-3 z-30 flex items-center gap-2 px-3 py-1.5 rounded-full bg-red-600/90 text-white text-xs shadow-lg">
          <span className="w-2 h-2 rounded-full bg-white animate-pulse" />
          {role === 'controller' ? `正在控制「${peerName}」` : `正在被「${peerName}」控制`}
          <button
            type="button"
            onClick={() => endSession()}
            className="px-2 py-0.5 rounded bg-white/20 hover:bg-white/30"
          >
            结束
          </button>
        </div>
      )}

      {/* 被控端授权弹窗 */}
      {incomingRequest && (
        <div className="absolute inset-0 z-40 flex items-center justify-center bg-black/50">
          <div className="card p-6 w-80 text-center bg-white text-slate-800">
            <MonitorUp className="w-10 h-10 mx-auto mb-3 text-brand-600" />
            <h3 className="font-semibold mb-1">远程控制请求</h3>
            <p className="text-sm text-slate-500 mb-4">
              「{incomingRequest.name}」请求控制你的电脑，是否允许？
            </p>
            <div className="flex gap-2 justify-center">
              <button type="button" className="btn-secondary" onClick={rejectControl}>拒绝</button>
              <button
                type="button"
                className="px-4 py-2 rounded-lg bg-brand-600 text-white text-sm hover:bg-brand-700"
                onClick={() => void acceptControl()}
              >
                允许控制
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 代理缺失引导（被控端） */}
      {agentMissing && (
        <div className="absolute inset-0 z-40 flex items-center justify-center bg-black/50">
          <div className="card p-6 w-96 bg-white text-slate-800">
            <XCircle className="w-8 h-8 mb-2 text-amber-500" />
            <h3 className="font-semibold mb-1">需要运行远程控制代理</h3>
            <p className="text-sm text-slate-500 mb-3">
              远程控制需要在本机运行桌面代理（desktop-agent.exe）。请启动后重试。
              代理仅监听本机回环地址，会话需一次性令牌，Ctrl+Alt+Esc 可随时强制结束。
            </p>
            <button
              type="button"
              className="btn-secondary"
              onClick={() => useRemoteControlStore.setState({ agentMissing: false })}
            >
              知道了
            </button>
          </div>
        </div>
      )}

      {/* 一次性提示 */}
      {notice && (
        <div className="absolute top-20 left-1/2 -translate-x-1/2 z-30 px-4 py-1.5 rounded-full bg-slate-800/90 text-white text-xs shadow-lg pointer-events-none">
          {notice}
        </div>
      )}
    </>
  );
}

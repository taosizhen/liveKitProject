// 被控端本地桌面代理（desktop-agent.exe）的 HTTP/WebSocket 客户端
// 代理仅监听 127.0.0.1:17653；会话需一次性 token（POST /session 获取，WS 握手时消费）

const AGENT_BASE = 'http://127.0.0.1:17653';
const AGENT_WS = 'ws://127.0.0.1:17653/control';

/** 探测本地代理是否运行（1.5s 超时） */
export async function checkAgent(): Promise<boolean> {
  try {
    const ctrl = new AbortController();
    const timer = window.setTimeout(() => ctrl.abort(), 1500);
    const resp = await fetch(`${AGENT_BASE}/status`, { signal: ctrl.signal });
    window.clearTimeout(timer);
    return resp.ok;
  } catch {
    return false;
  }
}

/** 创建一次性会话 token（已有活跃会话时抛错） */
export async function createSession(): Promise<string> {
  const resp = await fetch(`${AGENT_BASE}/session`, { method: 'POST' });
  if (!resp.ok) throw new Error('代理已有进行中的控制会话');
  const data = (await resp.json()) as { ok: boolean; token?: string };
  if (!data.ok || !data.token) throw new Error('创建控制会话失败');
  return data.token;
}

/**
 * 与本地代理建立控制 WebSocket
 * @param token 一次性会话 token
 * @param onInput 业务层调用：发送输入事件（归一化坐标）
 * @returns 连接就绪的 WebSocket；失败抛错
 */
export function connectAgent(token: string): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`${AGENT_WS}?token=${encodeURIComponent(token)}`);
    const timer = window.setTimeout(() => {
      ws.close();
      reject(new Error('连接本地代理超时'));
    }, 3000);
    ws.onmessage = (e) => {
      try {
        const msg = JSON.parse(String(e.data)) as { type?: string };
        if (msg.type === 'ready') {
          window.clearTimeout(timer);
          resolve(ws);
        } else if (msg.type === 'error') {
          window.clearTimeout(timer);
          ws.close();
          reject(new Error('代理拒绝了会话 token'));
        }
      } catch {
        // 忽略非 JSON 消息
      }
    };
    ws.onerror = () => {
      window.clearTimeout(timer);
      reject(new Error('无法连接本地代理'));
    };
    ws.onclose = () => {
      window.clearTimeout(timer);
      reject(new Error('本地代理连接已断开'));
    };
  });
}

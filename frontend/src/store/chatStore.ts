// 实时聊天 store：WebSocket + HTTP 历史
import { create } from 'zustand';
import { tokenStorage, resolveAPI, resolveWS } from '@/api/http';
import type { ChatMessage } from '@/types';

interface ChatState {
  messages: ChatMessage[];
  connected: boolean;
  error: string | null;
  ws: WebSocket | null;
  loadHistory: (meetingID: string) => Promise<void>;
  connect: (meetingID: string) => void;
  disconnect: () => void;
  send: (content: string) => void;
}

/** 历史消息持久化 + WS 实时订阅 store */
export const useChatStore = create<ChatState>((set, get) => ({
  messages: [],
  connected: false,
  error: null,
  ws: null,

  /** HTTP 拉取历史消息 */
  loadHistory: async (meetingID: string) => {
    const token = tokenStorage.access;
    if (!token) return;
    try {
      const res = await fetch(resolveAPI(`/api/v1/meetings/${meetingID}/chat/history?limit=100`), {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const body = await res.json();
        set({ messages: body.data ?? [] });
      }
    } catch (e) {
      console.warn('[chat] load history fail', e);
    }
  },

  /** 建立 WebSocket 连接 */
  connect: (meetingID: string) => {
    const { ws: existing } = get();
    if (existing) {
      try { existing.close(); } catch {}
    }
    const token = tokenStorage.access;
    if (!token) return;
    const url = resolveWS(`/api/v1/ws/meetings/${meetingID}/chat?token=${token}`);
    const ws = new WebSocket(url);

    ws.onopen = () => {
      set({ connected: true, ws, error: null });
    };

    ws.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data);
        if (data.type === 'chat') {
          const msg: ChatMessage = {
            id: crypto.randomUUID(),
            meeting_id: meetingID,
            user_id: data.user_id ?? '',
            content: data.content ?? '',
            created_at: new Date(data.timestamp).toISOString(),
            user: data.user_name ? { id: data.user_id, name: data.user_name } : undefined,
          };
          set((s) => ({ messages: [...s.messages, msg] }));
        } else if (data.type === 'system') {
          const msg: ChatMessage = {
            id: crypto.randomUUID(),
            meeting_id: meetingID,
            user_id: '',
            content: `${data.user_name ?? 'someone'} ${data.info}`,
            created_at: new Date(data.timestamp).toISOString(),
          };
          set((s) => ({ messages: [...s.messages, msg] }));
        }
      } catch (e) {
        console.warn('[chat] parse msg fail', e);
      }
    };

    ws.onerror = () => {
      set({ error: 'ws error', connected: false });
    };

    ws.onclose = () => {
      set({ connected: false, ws: null });
    };
  },

  disconnect: () => {
    const { ws } = get();
    if (ws) {
      try { ws.close(); } catch {}
    }
    set({ ws: null, connected: false });
  },

  send: (content: string) => {
    const { ws } = get();
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'chat', content }));
    }
  },
}));

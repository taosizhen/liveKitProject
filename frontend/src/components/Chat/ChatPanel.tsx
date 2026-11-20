// ChatPanel：WebSocket 增强的会议内聊天面板（可嵌入会议室侧边栏）
import { useEffect, useRef, useState } from 'react';
import { MessageCircle, Send, Users } from 'lucide-react';
import { useChatStore } from '@/store/chatStore';

interface Props {
  meetingID: string;
  className?: string;
}

/** 实时聊天面板：历史消息 + WS 实时消息 + 输入框 */
export default function ChatPanel({ meetingID, className }: Props) {
  const { messages, connected, loadHistory, connect, disconnect, send } = useChatStore();
  const scrollRef = useRef<HTMLDivElement>(null);
  const [input, setInput] = useState('');

  useEffect(() => {
    if (!meetingID) return;
    loadHistory(meetingID);
    connect(meetingID);
    return () => disconnect();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [meetingID]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' });
  }, [messages.length]);

  const onSend = () => {
    const text = input.trim();
    if (!text) return;
    send(text);
    setInput('');
  };

  return (
    <div className={`flex flex-col h-full bg-slate-800/80 backdrop-blur-sm rounded-lg border border-slate-700 ${className ?? ''}`}>
      <div className="px-4 py-3 border-b border-slate-700/60 flex items-center gap-2">
        <MessageCircle className="w-4 h-4 text-brand-400" />
        <span className="text-sm font-medium text-white">会议聊天</span>
        <span className={`ml-auto text-xs px-2 py-0.5 rounded-full ${connected ? 'bg-green-500/20 text-green-300' : 'bg-slate-600/50 text-slate-300'}`}>
          {connected ? '● 在线' : '○ 离线'}
        </span>
        <Users className="w-4 h-4 text-slate-400" />
      </div>

      <div ref={scrollRef} className="flex-1 overflow-y-auto px-4 py-3 space-y-3">
        {messages.length === 0 && (
          <div className="text-center text-slate-400 text-sm py-10">
            暂无消息，发个招呼吧 👋
          </div>
        )}
        {messages.map((m) => {
          const isSystem = !m.user_id;
          return (
            <div key={m.id} className={`text-sm ${isSystem ? 'text-slate-400 text-center italic text-xs' : ''}`}>
              {!isSystem && (
                <div className="text-xs text-slate-400 mb-0.5">
                  {m.user?.name ?? '匿名'}
                </div>
              )}
              <div className={`${isSystem ? 'bg-transparent text-slate-400' : 'bg-slate-700/70 text-white rounded-lg px-3 py-1.5 inline-block max-w-full break-words'}`}>
                {m.content}
              </div>
            </div>
          );
        })}
      </div>

      <div className="px-3 py-2 border-t border-slate-700/60 flex gap-2">
        <input
          className="flex-1 text-sm px-3 py-2 bg-slate-900/80 text-white placeholder-slate-400 border border-slate-600 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/40 focus:border-brand-500/60"
          placeholder={connected ? '输入消息...' : '连接中...'}
          disabled={!connected}
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') onSend(); }}
        />
        <button
          className="btn-primary px-3 py-2 disabled:opacity-40"
          disabled={!connected || !input.trim()}
          onClick={onSend}
        >
          <Send className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
}

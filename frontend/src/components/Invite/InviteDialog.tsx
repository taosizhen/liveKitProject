// InviteDialog：组织者邀请参会者弹窗（搜索用户 + 多选 + 提交）
import { useEffect, useState } from 'react';
import { Search, Check, X } from 'lucide-react';
import * as meetingApi from '@/api/meeting';

interface UserSuggest {
  id: string;
  name: string;
  email: string;
  role_name?: string;
}

interface Props {
  meetingID: string;
  /** 已在会中的用户 ID 集合（排除组织者 + 已邀请者） */
  excludeIDs: Set<string>;
  onClose: () => void;
  onInvited: () => void;
}

/** 组织者邀请参会者对话框 */
export default function InviteDialog({ meetingID, excludeIDs, onClose, onInvited }: Props) {
  const [query, setQuery] = useState('');
  const [all, setAll] = useState<UserSuggest[]>([]);
  const [loading, setLoading] = useState(false);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState(false);

  const search = async (q: string) => {
    setLoading(true);
    try {
      const resp = await meetingApi.suggestUsers(q);
      setAll(resp.data ?? []);
    } catch {}
    setLoading(false);
  };

  /** 搜索用户列表（q 变化时触发） */
  useEffect(() => {
    search(query);
  }, [query]);

  const toggle = (id: string) => {
    setSelected((prev) => {
      const n = new Set(prev);
      if (n.has(id)) n.delete(id);
      else n.add(id);
      return n;
    });
  };

  const submit = async () => {
    if (selected.size === 0) return;
    setBusy(true);
    try {
      await meetingApi.inviteParticipants(meetingID, Array.from(selected));
      onInvited();
    } catch {}
    setBusy(false);
  };

  const filtered = all.filter((u) => !excludeIDs.has(u.id));

  return (
    <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4" onClick={onClose}>
      <div className="bg-white rounded-xl shadow-xl w-full max-w-lg" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between p-4 border-b border-slate-100">
          <h3 className="font-semibold text-slate-800">邀请参会者</h3>
          <button onClick={onClose}><X className="w-5 h-5 text-slate-400" /></button>
        </div>

        <div className="p-4">
          <div className="relative mb-3">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
            <input
              className="input pl-9"
              placeholder="输入姓名或邮箱搜索..."
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              autoFocus
            />
          </div>

          <div className="max-h-80 overflow-y-auto border border-slate-100 rounded-lg divide-y divide-slate-50">
            {loading ? (
              <div className="p-6 text-center text-slate-400 text-sm">加载中...</div>
            ) : filtered.length === 0 ? (
              <div className="p-6 text-center text-slate-400 text-sm">
                {query ? '无匹配用户' : '系统还没有其他用户'}
              </div>
            ) : (
              filtered.map((u) => {
                const chosen = selected.has(u.id);
                return (
                  <button
                    key={u.id}
                    className={`w-full flex items-center gap-3 px-3 py-2.5 text-left transition ${
                      chosen ? 'bg-brand-50' : 'hover:bg-slate-50'
                    }`}
                    onClick={() => toggle(u.id)}
                  >
                    <div className={`w-5 h-5 rounded border-2 flex items-center justify-center transition ${
                      chosen ? 'bg-brand-500 border-brand-500' : 'border-slate-300'
                    }`}>
                      {chosen && <Check className="w-3.5 h-3.5 text-white" />}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="text-sm font-medium text-slate-800 truncate">{u.name}</div>
                      <div className="text-xs text-slate-500 truncate">{u.email}</div>
                    </div>
                    {u.role_name && (
                      <span className="text-xs text-slate-400 shrink-0">
                        {u.role_name === 'admin' ? '管理员' : u.role_name === 'teacher' ? '老师' : '学员'}
                      </span>
                    )}
                  </button>
                );
              })
            )}
          </div>
        </div>

        <div className="flex items-center justify-between p-4 border-t border-slate-100">
          <div className="text-sm text-slate-500">已选 {selected.size} 人</div>
          <div className="flex gap-2">
            <button className="btn-secondary" onClick={onClose}>取消</button>
            <button className="btn-primary" disabled={selected.size === 0 || busy} onClick={submit}>
              {busy ? '邀请中...' : `邀请 ${selected.size} 人`}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

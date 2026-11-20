// UserManagement：管理员用户管理页（创建/搜索/改角色/封禁）
import { useEffect, useState } from 'react';
import { Users, Plus, Search, Edit3, Ban, CheckCircle, X } from 'lucide-react';
import { useAuthStore } from '@/store/authStore';
import { tokenStorage, resolveAPI } from '@/api/http';

interface UserRow {
  id: string; email: string; name: string; role_name?: string; status: string; created_at: string;
}

/** 管理员用户管理页 */
export default function UserManagement() {
  const user = useAuthStore((s) => s.user);
  const token = tokenStorage.access;
  const [list, setList] = useState<UserRow[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [role, setRole] = useState('');
  const [showCreate, setShowCreate] = useState(false);

  const load = async () => {
    if (!token) return;
    const params = new URLSearchParams({ page: String(page), page_size: '15' });
    if (search) params.set('search', search);
    if (role) params.set('role', role);
    const res = await fetch(resolveAPI(`/api/v1/users?${params}`), { headers: { Authorization: `Bearer ${token}` } });
    if (res.ok) {
      const body = await res.json();
      setList(body.items ?? []);
      setTotal(body.total ?? 0);
    }
  };

  useEffect(() => { load(); }, [page, role]);

  const onToggleStatus = async (id: string, current: string) => {
    if (!token) return;
    const next = current === 'active' ? 'disabled' : 'active';
    await fetch(resolveAPI(`/api/v1/users/${id}`), {
      method: 'PATCH',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: next }),
    });
    load();
  };

  const onChangeRole = async (id: string, newRole: string) => {
    if (!token) return;
    await fetch(resolveAPI(`/api/v1/users/${id}`), {
      method: 'PATCH',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ role: newRole }),
    });
    load();
  };

  if (user?.role !== 'admin') {
    return (
      <div className="card p-8 text-center max-w-md mx-auto mt-12">
        <div className="text-slate-500">仅管理员可访问此页面</div>
      </div>
    );
  }

  return (
    <div className="space-y-5">
      {/* 头部 */}
      <div className="card p-5 flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold text-slate-800">用户管理</h2>
          <p className="text-sm text-slate-500">共 {total} 个账号</p>
        </div>
        <button className="btn-primary flex items-center gap-2" onClick={() => setShowCreate(true)}>
          <Plus className="w-4 h-4" /> 创建账号
        </button>
      </div>

      {/* 筛选 */}
      <div className="card p-4 flex items-center gap-3">
        <div className="flex items-center gap-2 flex-1">
          <Search className="w-4 h-4 text-slate-400" />
          <input
            className="flex-1 text-sm px-3 py-1.5 border border-slate-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500/30"
            placeholder="搜索姓名或邮箱..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && load()}
          />
          <button className="btn-secondary text-sm py-1.5 px-3" onClick={load}>搜索</button>
        </div>
        <select className="text-sm px-3 py-1.5 border border-slate-200 rounded-lg"
          value={role} onChange={(e) => { setRole(e.target.value); setPage(1); }}>
          <option value="">全部角色</option>
          <option value="admin">管理员</option>
          <option value="teacher">老师</option>
          <option value="student">学员</option>
        </select>
      </div>

      {/* 表格 */}
      <div className="card p-0 overflow-hidden">
        <table className="table">
          <thead>
            <tr>
              <th>用户</th><th>邮箱</th><th>角色</th><th>状态</th><th className="text-right">操作</th>
            </tr>
          </thead>
          <tbody>
            {list.map((u) => (
              <tr key={u.id}>
                <td className="font-medium text-slate-800">{u.name}</td>
                <td className="text-slate-600">{u.email}</td>
                <td>
                  <select className="text-xs border border-slate-200 rounded px-2 py-1"
                    value={u.role_name ?? 'student'}
                    onChange={(e) => onChangeRole(u.id, e.target.value)}>
                    <option value="admin">管理员</option>
                    <option value="teacher">老师</option>
                    <option value="student">学员</option>
                  </select>
                </td>
                <td>
                  {u.status === 'active' ? (
                    <span className="inline-flex items-center gap-1 text-green-600 text-xs">
                      <CheckCircle className="w-3.5 h-3.5" /> 活跃
                    </span>
                  ) : (
                    <span className="inline-flex items-center gap-1 text-slate-400 text-xs">
                      <Ban className="w-3.5 h-3.5" /> 已禁用
                    </span>
                  )}
                </td>
                <td className="text-right">
                  {u.id !== user?.id && (
                    <button
                      className="btn-ghost text-slate-500 hover:text-red-500"
                      onClick={() => onToggleStatus(u.id, u.status)}
                      title={u.status === 'active' ? '禁用' : '启用'}
                    >
                      {u.status === 'active' ? <Ban className="w-4 h-4" /> : <CheckCircle className="w-4 h-4" />}
                    </button>
                  )}
                </td>
              </tr>
            ))}
            {list.length === 0 && (
              <tr><td colSpan={5} className="text-center text-slate-400 py-8">暂无用户</td></tr>
            )}
          </tbody>
        </table>
      </div>

      {showCreate && <CreateUserDialog onClose={() => setShowCreate(false)} onCreated={() => { setShowCreate(false); load(); }} />}
    </div>
  );
}

/** 创建账号弹窗 */
function CreateUserDialog({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
  const token = tokenStorage.access;
  const [form, setForm] = useState({ email: '', name: '', password: '', role: 'student' });
  const [err, setErr] = useState('');

  const submit = async () => {
    setErr('');
    const res = await fetch(resolveAPI('/api/v1/users'), {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(form),
    });
    if (res.ok) {
      onCreated();
    } else {
      const body = await res.json();
      setErr(body.error ?? '创建失败');
    }
  };

  return (
    <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50" onClick={onClose}>
      <div className="bg-white rounded-xl shadow-xl p-6 w-full max-w-md" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-4">
          <h3 className="font-semibold text-slate-800 flex items-center gap-2"><Users className="w-5 h-5 text-brand-600" /> 创建用户</h3>
          <button onClick={onClose}><X className="w-5 h-5 text-slate-400" /></button>
        </div>
        <div className="space-y-3 text-sm">
          <input className="input" placeholder="姓名" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
          <input className="input" placeholder="邮箱" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} />
          <input className="input" type="password" placeholder="密码（≥6位）" value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} />
          <select className="input" value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value })}>
            <option value="student">学员</option>
            <option value="teacher">老师</option>
            <option value="admin">管理员</option>
          </select>
          {err && <div className="text-red-500 text-xs">{err}</div>}
        </div>
        <div className="mt-5 flex justify-end gap-2">
          <button className="btn-secondary" onClick={onClose}>取消</button>
          <button className="btn-primary flex items-center gap-1" onClick={submit}><Edit3 className="w-4 h-4" /> 创建</button>
        </div>
      </div>
    </div>
  );
}

// 应用主 Layout：侧边栏 + 顶部导航 + 内容区域
import { useRef, useState } from 'react';
import { Outlet, useLocation, useNavigate } from 'react-router-dom';
import { Home, CalendarDays, Video, LogOut, UserCircle, Users, Loader2, Pencil, Check, X } from 'lucide-react';
import { useAuthStore } from '@/store/authStore';

const navItems = [
  { path: '/dashboard', label: '工作台', icon: Home },
  { path: '/meetings', label: '会议管理', icon: CalendarDays },
];

export default function Layout() {
  const location = useLocation();
  const navigate = useNavigate();
  const { user, logout, uploadAvatar, updateName } = useAuthStore();

  const avatarInputRef = useRef<HTMLInputElement>(null);
  const [avatarUploading, setAvatarUploading] = useState(false);
  const [avatarError, setAvatarError] = useState<string | null>(null);

  // 昵称编辑
  const [editingName, setEditingName] = useState(false);
  const [nameDraft, setNameDraft] = useState('');
  const [nameSaving, setNameSaving] = useState(false);
  const [nameError, setNameError] = useState<string | null>(null);

  /** 开始编辑昵称：用当前值预填 */
  const startEditName = () => {
    setNameDraft(user?.name || '');
    setNameError(null);
    setEditingName(true);
  };

  /** 保存昵称 */
  const handleSaveName = async () => {
    const trimmed = nameDraft.trim();
    if (!trimmed) {
      setNameError('昵称不能为空');
      return;
    }
    if (trimmed.length > 50) {
      setNameError('昵称最多 50 个字符');
      return;
    }
    setNameSaving(true);
    setNameError(null);
    try {
      await updateName(trimmed);
      setEditingName(false);
    } catch (err) {
      setNameError((err as Error).message || '修改失败');
    } finally {
      setNameSaving(false);
    }
  };

  /** 选择图片后上传头像 */
  const handleAvatarChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = ''; // 允许重复选择同一文件
    if (!file) return;
    setAvatarError(null);
    setAvatarUploading(true);
    try {
      await uploadAvatar(file);
    } catch (err) {
      setAvatarError((err as Error).message);
    } finally {
      setAvatarUploading(false);
    }
  };

  const roleBadge: Record<string, string> = {
    admin: 'badge-danger',
    teacher: 'badge-info',
    student: 'badge-gray',
  };

  return (
    <div className="flex h-screen bg-slate-50">
      {/* ====== 侧边栏 ====== */}
      <aside className="w-60 bg-white border-r border-slate-200 flex flex-col shrink-0">
        {/* Logo */}
        <div className="h-16 flex items-center gap-2 px-5 border-b border-slate-100">
          <div className="w-8 h-8 rounded-lg bg-brand-600 flex items-center justify-center">
            <Video className="w-5 h-5 text-white" />
          </div>
          <span className="font-semibold text-slate-800">会议协助平台</span>
        </div>

        {/* 导航菜单 */}
        <nav className="flex-1 py-4 px-3 space-y-1">
          {navItems.map((item) => {
            const Icon = item.icon;
            const active = location.pathname.startsWith(item.path);
            return (
              <button
                key={item.path}
                onClick={() => navigate(item.path)}
                className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition ${
                  active
                    ? 'bg-brand-50 text-brand-700'
                    : 'text-slate-600 hover:bg-slate-50 hover:text-slate-800'
                }`}
              >
                <Icon className="w-4 h-4" />
                {item.label}
              </button>
            );
          })}

          {/* 管理员专属：用户管理 */}
          {user?.role === 'admin' && (
            <button
              onClick={() => navigate('/admin/users')}
              className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition ${
                location.pathname.startsWith('/admin')
                  ? 'bg-brand-50 text-brand-700'
                  : 'text-slate-600 hover:bg-slate-50 hover:text-slate-800'
              }`}
            >
              <Users className="w-4 h-4" />
              用户管理
            </button>
          )}
        </nav>

        {/* 用户信息 */}
        <div className="border-t border-slate-100 p-4">
          <div className="flex items-center gap-3">
            {/* 头像：点击可上传更换（/storage 由 Vite 代理到后端） */}
            <button
              type="button"
              onClick={() => avatarInputRef.current?.click()}
              title="点击更换头像"
              className="relative w-9 h-9 rounded-full bg-slate-100 flex items-center justify-center overflow-hidden shrink-0 group"
            >
              {avatarUploading ? (
                <Loader2 className="w-4 h-4 text-slate-400 animate-spin" />
              ) : user?.avatar_url ? (
                <img src={user.avatar_url} alt="头像" className="w-full h-full object-cover" />
              ) : (
                <UserCircle className="w-5 h-5 text-slate-400" />
              )}
              <span className="absolute inset-0 bg-black/30 text-white text-[10px] hidden group-hover:flex items-center justify-center">
                更换
              </span>
            </button>
            <input
              ref={avatarInputRef}
              type="file"
              accept="image/jpeg,image/png,image/webp,image/gif"
              className="hidden"
              onChange={handleAvatarChange}
            />
            <div className="flex-1 min-w-0">
              {editingName ? (
                <div className="flex items-center gap-1">
                  <input
                    autoFocus
                    value={nameDraft}
                    maxLength={50}
                    onChange={(e) => setNameDraft(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') handleSaveName();
                      if (e.key === 'Escape') setEditingName(false);
                    }}
                    className="w-full min-w-0 px-1.5 py-0.5 text-sm border border-indigo-300 rounded focus:outline-none focus:ring-1 focus:ring-indigo-400"
                  />
                  <button
                    type="button"
                    onClick={handleSaveName}
                    disabled={nameSaving}
                    className="p-0.5 text-emerald-600 hover:bg-emerald-50 rounded"
                    title="保存"
                  >
                    {nameSaving ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Check className="w-3.5 h-3.5" />}
                  </button>
                  <button
                    type="button"
                    onClick={() => setEditingName(false)}
                    className="p-0.5 text-slate-400 hover:bg-slate-100 rounded"
                    title="取消"
                  >
                    <X className="w-3.5 h-3.5" />
                  </button>
                </div>
              ) : (
                <div className="flex items-center gap-1">
                  <span className="text-sm font-medium text-slate-800 truncate">
                    {user?.name || '未登录'}
                  </span>
                  {user && (
                    <button
                      type="button"
                      onClick={startEditName}
                      className="p-0.5 text-slate-300 hover:text-indigo-500 hover:bg-slate-100 rounded"
                      title="修改昵称"
                    >
                      <Pencil className="w-3 h-3" />
                    </button>
                  )}
                </div>
              )}
              {nameError && <div className="text-xs text-red-500 truncate">{nameError}</div>}
              <div className="text-xs text-slate-500 truncate">{user?.email}</div>
            </div>
          </div>
          {avatarError && <div className="mt-2 text-xs text-red-500 truncate">{avatarError}</div>}
          {user && (
            <div className="mt-3 flex items-center justify-between">
              <span className={`${roleBadge[user.role] || 'badge-gray'} capitalize`}>
                {user.role === 'admin' ? '管理员' : user.role === 'teacher' ? '辅导老师' : '学员'}
              </span>
              <button
                onClick={() => {
                  logout();
                  navigate('/login');
                }}
                className="text-slate-400 hover:text-red-500 transition p-1"
                title="退出登录"
              >
                <LogOut className="w-4 h-4" />
              </button>
            </div>
          )}
        </div>
      </aside>

      {/* ====== 主内容区 ====== */}
      <main className="flex-1 flex flex-col overflow-hidden">
        {/* 顶部 Header */}
        <header className="h-16 bg-white border-b border-slate-200 flex items-center px-8 shrink-0">
          <h1 className="page-title">
            {navItems.find((n) => location.pathname.startsWith(n.path))?.label || '会议协助平台'}
          </h1>
        </header>

        {/* 页面出口 */}
        <div className="flex-1 overflow-auto p-8">
          <Outlet />
        </div>
      </main>
    </div>
  );
}

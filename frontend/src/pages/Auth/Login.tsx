// 登录页 — 浅色极简风格
import { useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { Video, Eye, EyeOff } from 'lucide-react';
import { useAuthStore } from '@/store/authStore';

export default function Login() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const redirect = params.get('redirect') || '/dashboard';

  const login = useAuthStore((s) => s.login);
  const error = useAuthStore((s) => s.error);
  const loading = useAuthStore((s) => s.loading);
  const clearError = useAuthStore((s) => s.clearError);

  const [form, setForm] = useState({ email: '', password: '' });
  const [showPwd, setShowPwd] = useState(false);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    clearError();
    try {
      await login(form.email, form.password);
      navigate(redirect, { replace: true });
    } catch {
      // error 已在 store 中
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-slate-50 p-6">
      {/* 背景装饰 */}
      <div className="fixed inset-0 pointer-events-none overflow-hidden">
        <div className="absolute -top-40 -left-40 w-80 h-80 rounded-full bg-brand-100/60 blur-3xl" />
        <div className="absolute -bottom-40 -right-40 w-96 h-96 rounded-full bg-slate-100 blur-3xl" />
      </div>

      <div className="relative w-full max-w-md">
        {/* Logo */}
        <div className="flex items-center gap-2 justify-center mb-8">
          <div className="w-10 h-10 rounded-xl bg-brand-600 flex items-center justify-center shadow-sm">
            <Video className="w-6 h-6 text-white" />
          </div>
          <span className="text-xl font-semibold text-slate-800">会议协助平台</span>
        </div>

        {/* 登录卡片 */}
        <div className="card p-8">
          <h2 className="text-lg font-semibold text-slate-800 mb-1">欢迎回来</h2>
          <p className="text-sm text-slate-500 mb-6">登录以继续使用在线会议辅导</p>

          {error && (
            <div className="mb-4 px-3 py-2 rounded-lg bg-red-50 border border-red-200 text-sm text-red-700">
              {error}
            </div>
          )}

          <form onSubmit={onSubmit} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1.5">邮箱</label>
              <input
                type="email"
                className="input"
                placeholder="you@example.com"
                value={form.email}
                onChange={(e) => setForm({ ...form, email: e.target.value })}
                required
                autoComplete="email"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1.5">密码</label>
              <div className="relative">
                <input
                  type={showPwd ? 'text' : 'password'}
                  className="input pr-10"
                  placeholder="至少 6 位"
                  value={form.password}
                  onChange={(e) => setForm({ ...form, password: e.target.value })}
                  required
                  minLength={6}
                  autoComplete="current-password"
                />
                <button
                  type="button"
                  onClick={() => setShowPwd((v) => !v)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600"
                >
                  {showPwd ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>
            </div>

            <button type="submit" className="btn-primary w-full" disabled={loading}>
              {loading ? '登录中...' : '登录'}
            </button>
          </form>

          <p className="mt-6 text-center text-sm text-slate-500">
            还没有账号？
            <Link to="/register" className="ml-1 text-brand-600 hover:text-brand-700 font-medium">
              立即注册
            </Link>
          </p>

          <div className="mt-6 pt-4 border-t border-slate-100 text-center">
            <p className="text-xs text-slate-400">
              演示账号: admin@demo.com / admin123
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}

// App 路由配置：公开路由 + 受保护路由
import { Routes, Route, Navigate } from 'react-router-dom';
import { useAuthStore } from '@/store/authStore';
import Layout from '@/components/Layout/Layout';
import Login from '@/pages/Auth/Login';
import Register from '@/pages/Auth/Register';
import Dashboard from '@/pages/Dashboard/Dashboard';
import MeetingList from '@/pages/Meetings/MeetingList';
import MeetingCreate from '@/pages/Meetings/MeetingCreate';
import MeetingDetail from '@/pages/Meetings/MeetingDetail';
import Room from '@/pages/Room/Room';
import UserManagement from '@/pages/Admin/UserManagement';
import NotFound from '@/pages/NotFound';

/** 路由守卫组件：仅 admin 角色可访问 */
function RequireAdmin({ children }: { children: React.ReactNode }) {
  const user = useAuthStore((s) => s.user);
  if (!user) return <Navigate to="/login" replace />;
  if (user.role !== 'admin') return <Navigate to="/dashboard" replace />;
  return <>{children}</>;
}

/** 路由守卫组件：未登录自动跳转登录页 */
function RequireAuth({ children }: { children: React.ReactNode }) {
  const user = useAuthStore((s) => s.user);
  if (!user) {
    return <Navigate to="/login" replace />;
  }
  return <>{children}</>;
}

/** 路由守卫组件：已登录则跳转工作台 */
function RequireGuest({ children }: { children: React.ReactNode }) {
  const user = useAuthStore((s) => s.user);
  if (user) {
    return <Navigate to="/dashboard" replace />;
  }
  return <>{children}</>;
}

export default function AppRouter() {
  return (
    <Routes>
      {/* 公开路由 */}
      <Route path="/login" element={<RequireGuest><Login /></RequireGuest>} />
      <Route path="/register" element={<RequireGuest><Register /></RequireGuest>} />

      {/* 根路径重定向 */}
      <Route path="/" element={<Navigate to="/dashboard" replace />} />

      {/* 受保护路由：全部包裹在 Layout 里 */}
      <Route element={<Layout />}>
        <Route path="/dashboard" element={<RequireAuth><Dashboard /></RequireAuth>} />
        <Route path="/meetings" element={<RequireAuth><MeetingList /></RequireAuth>} />
        <Route path="/meetings/new" element={<RequireAuth><MeetingCreate /></RequireAuth>} />
        <Route path="/meetings/:id" element={<RequireAuth><MeetingDetail /></RequireAuth>} />
        <Route path="/admin/users" element={<RequireAdmin><UserManagement /></RequireAdmin>} />
      </Route>

      {/* 会议室：全屏，不带 Layout */}
      <Route path="/room/:id" element={<RequireAuth><Room /></RequireAuth>} />

      {/* 404 */}
      <Route path="*" element={<NotFound />} />
    </Routes>
  );
}

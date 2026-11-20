// 404 页面
import { Link } from 'react-router-dom';
import { Home } from 'lucide-react';

export default function NotFound() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-slate-50">
      <div className="text-center">
        <h1 className="text-7xl font-bold text-brand-600 mb-2">404</h1>
        <p className="text-lg text-slate-600 mb-6">页面走丢了</p>
        <Link to="/dashboard" className="btn-primary inline-flex">
          <Home className="w-4 h-4" />
          返回工作台
        </Link>
      </div>
    </div>
  );
}

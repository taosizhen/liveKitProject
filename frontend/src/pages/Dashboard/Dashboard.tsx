// 工作台：展示今日会议、快速入口
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { CalendarDays, Plus, Video, Users } from 'lucide-react';
import { useAuthStore } from '@/store/authStore';
import * as meetingApi from '@/api/meeting';
import type { Meeting, PageData } from '@/types';

/** 状态标签 */
function StatusBadge({ status }: { status: Meeting['status'] }) {
  const map: Record<Meeting['status'], { label: string; cls: string }> = {
    scheduled: { label: '待开始', cls: 'badge-info' },
    in_progress: { label: '进行中', cls: 'badge-success' },
    completed: { label: '已结束', cls: 'badge-gray' },
    cancelled: { label: '已取消', cls: 'badge-danger' },
  };
  const { label, cls } = map[status];
  return <span className={cls}>{label}</span>;
}

export default function Dashboard() {
  const navigate = useNavigate();
  const user = useAuthStore((s) => s.user);
  const [meetings, setMeetings] = useState<PageData<Meeting> | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const resp = await meetingApi.listMeetings({ page: 1, page_size: 5 });
        setMeetings(resp.data!);
      } catch {
        // 忽略错误
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  const stats = [
    { label: '我的会议', value: meetings?.total ?? 0, icon: CalendarDays, color: 'bg-blue-500' },
    { label: '进行中', value: meetings?.items.filter((m) => m.status === 'in_progress').length ?? 0, icon: Video, color: 'bg-green-500' },
    { label: '参与者', value: meetings?.items.reduce((acc, m) => acc + (m.participants?.length ?? 0), 0) ?? 0, icon: Users, color: 'bg-amber-500' },
  ];

  return (
    <div className="space-y-6">
      {/* 欢迎条 */}
      <div className="card p-6 flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold text-slate-800">
            你好，{user?.name || '同学'} 👋
          </h2>
          <p className="text-sm text-slate-500 mt-1">
            {user?.role === 'teacher' || user?.role === 'admin'
              ? '今天有什么辅导计划？'
              : '查看你的辅导安排，准时参加会议'}
          </p>
        </div>
        {(user?.role === 'teacher' || user?.role === 'admin') && (
          <button className="btn-primary" onClick={() => navigate('/meetings/new')}>
            <Plus className="w-4 h-4" />
            创建会议
          </button>
        )}
      </div>

      {/* 统计卡 */}
      <div className="grid grid-cols-3 gap-4">
        {stats.map((s) => {
          const Icon = s.icon;
          return (
            <div key={s.label} className="card p-5">
              <div className="flex items-center gap-3">
                <div className={`w-10 h-10 rounded-lg ${s.color} flex items-center justify-center`}>
                  <Icon className="w-5 h-5 text-white" />
                </div>
                <div>
                  <div className="text-2xl font-semibold text-slate-800">{s.value}</div>
                  <div className="text-xs text-slate-500">{s.label}</div>
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* 最近会议 */}
      <div className="card">
        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between">
          <h3 className="font-medium text-slate-800">最近会议</h3>
          <button className="text-sm text-brand-600 hover:text-brand-700" onClick={() => navigate('/meetings')}>
            查看全部 →
          </button>
        </div>
        {loading ? (
          <div className="p-8 text-center text-slate-400 text-sm">加载中...</div>
        ) : !meetings || meetings.items.length === 0 ? (
          <div className="p-12 text-center text-slate-400">
            <CalendarDays className="w-10 h-10 mx-auto mb-3 opacity-50" />
            <p>还没有会议安排</p>
          </div>
        ) : (
          <table className="table">
            <thead>
              <tr>
                <th>会议主题</th>
                <th>时间</th>
                <th>类型</th>
                <th>状态</th>
                <th className="text-right">操作</th>
              </tr>
            </thead>
            <tbody>
              {meetings.items.map((m) => (
                <tr key={m.id} className="cursor-pointer hover:bg-slate-50" onClick={() => navigate(`/meetings/${m.id}`)}>
                  <td className="font-medium text-slate-800">{m.title}</td>
                  <td className="text-slate-600">
                    {new Date(m.start_time).toLocaleString('zh-CN')}
                  </td>
                  <td className="text-slate-500 text-sm">
                    {m.meeting_type === 'tutoring' ? '一对一辅导' : m.meeting_type === 'group_class' ? '小组课' : 'Webinar'}
                  </td>
                  <td><StatusBadge status={m.status} /></td>
                  <td className="text-right">
                    {m.status === 'scheduled' || m.status === 'in_progress' ? (
                      <button
                        className="btn-ghost text-brand-600 hover:text-brand-700"
                        onClick={(e) => {
                          e.stopPropagation();
                          navigate(`/room/${m.id}`);
                        }}
                      >
                        <Video className="w-4 h-4" />
                        {m.status === 'in_progress' ? '进入会议' : '准备'}
                      </button>
                    ) : null}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

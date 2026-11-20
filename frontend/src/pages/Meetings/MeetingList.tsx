// 会议列表页：表格 + 筛选
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Plus, Video, CalendarDays } from 'lucide-react';
import { useAuthStore } from '@/store/authStore';
import * as meetingApi from '@/api/meeting';
import type { Meeting, PageData, MeetingStatus } from '@/types';

const STATUS_FILTER: { value: MeetingStatus | ''; label: string }[] = [
  { value: '', label: '全部' },
  { value: 'scheduled', label: '待开始' },
  { value: 'in_progress', label: '进行中' },
  { value: 'completed', label: '已结束' },
  { value: 'cancelled', label: '已取消' },
];

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

export default function MeetingList() {
  const navigate = useNavigate();
  const user = useAuthStore((s) => s.user);
  const [page, setPage] = useState(1);
  const [status, setStatus] = useState<MeetingStatus | ''>('');
  const [data, setData] = useState<PageData<Meeting> | null>(null);
  const [loading, setLoading] = useState(true);

  const isTeacher = user?.role === 'teacher' || user?.role === 'admin';

  const load = async () => {
    setLoading(true);
    try {
      const resp = await meetingApi.listMeetings({ page, page_size: 10, status: status || undefined });
      setData(resp.data!);
    } catch {
      //
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, status]);

  return (
    <div className="space-y-4">
      {/* 工具栏 */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          {STATUS_FILTER.map((s) => (
            <button
              key={s.value}
              onClick={() => {
                setStatus(s.value);
                setPage(1);
              }}
              className={`px-3 py-1.5 rounded-lg text-sm font-medium transition ${
                status === s.value
                  ? 'bg-brand-600 text-white'
                  : 'bg-white border border-slate-200 text-slate-600 hover:bg-slate-50'
              }`}
            >
              {s.label}
            </button>
          ))}
        </div>
        {isTeacher && (
          <button className="btn-primary" onClick={() => navigate('/meetings/new')}>
            <Plus className="w-4 h-4" />
            创建会议
          </button>
        )}
      </div>

      {/* 表格 */}
      <div className="card">
        {loading ? (
          <div className="p-12 text-center text-slate-400 text-sm">加载中...</div>
        ) : !data || data.items.length === 0 ? (
          <div className="p-16 text-center text-slate-400">
            <CalendarDays className="w-12 h-12 mx-auto mb-4 opacity-50" />
            <p>暂无会议</p>
            {isTeacher && (
              <button className="btn-primary mt-4" onClick={() => navigate('/meetings/new')}>
                <Plus className="w-4 h-4" />
                创建第一个会议
              </button>
            )}
          </div>
        ) : (
          <>
            <table className="table">
              <thead>
                <tr>
                  <th>会议主题</th>
                  <th>组织者</th>
                  <th>开始时间</th>
                  <th>类型</th>
                  <th>状态</th>
                  <th className="text-right">操作</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((m) => (
                  <tr key={m.id} className="hover:bg-slate-50 cursor-pointer" onClick={() => navigate(`/meetings/${m.id}`)}>
                    <td className="font-medium text-slate-800">{m.title}</td>
                    <td className="text-slate-600">{m.organizer?.name || '-'}</td>
                    <td className="text-slate-600">{new Date(m.start_time).toLocaleString('zh-CN')}</td>
                    <td className="text-slate-500 text-sm">
                      {m.meeting_type === 'tutoring' ? '一对一辅导' : m.meeting_type === 'group_class' ? '小组课' : 'Webinar'}
                    </td>
                    <td><StatusBadge status={m.status} /></td>
                    <td className="text-right">
                      {(m.status === 'scheduled' || m.status === 'in_progress') && (
                        <button
                          className="btn-ghost text-brand-600 hover:text-brand-700"
                          onClick={(e) => {
                            e.stopPropagation();
                            navigate(`/room/${m.id}`);
                          }}
                        >
                          <Video className="w-4 h-4" />
                          {m.status === 'in_progress' ? '进入' : '准备'}
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            {/* 分页 */}
            {data.pages > 1 && (
              <div className="px-4 py-3 border-t border-slate-100 flex items-center justify-between">
                <span className="text-sm text-slate-500">
                  共 {data.total} 条 · 第 {page} / {data.pages} 页
                </span>
                <div className="flex gap-1">
                  <button
                    className="btn-ghost disabled:opacity-50"
                    disabled={page <= 1}
                    onClick={() => setPage((p) => Math.max(1, p - 1))}
                  >
                    上一页
                  </button>
                  <button
                    className="btn-ghost disabled:opacity-50"
                    disabled={page >= data.pages}
                    onClick={() => setPage((p) => p + 1)}
                  >
                    下一页
                  </button>
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}

// 创建会议页
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, Users } from 'lucide-react';
import { useMeetingStore } from '@/store/meetingStore';
import type { MeetingType } from '@/types';

const MEETING_TYPES: { value: MeetingType; label: string; desc: string }[] = [
  { value: 'tutoring', label: '一对一辅导', desc: '老师 + 学员 一对一' },
  { value: 'group_class', label: '小组课', desc: '多人互动课堂' },
  { value: 'webinar', label: 'Webinar', desc: '大型线上讲座' },
];

export default function MeetingCreate() {
  const navigate = useNavigate();
  const create = useMeetingStore((s) => s.create);

  const [form, setForm] = useState({
    title: '',
    description: '',
    // datetime-local 格式：YYYY-MM-DDTHH:mm
    start_time: new Date(Date.now() + 30 * 60 * 1000).toISOString().slice(0, 16),
    end_time: '',
    meeting_type: 'tutoring' as MeetingType,
  });
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      // 转换为 RFC3339
      const startTimeRFC = new Date(form.start_time).toISOString();
      const endTimeRFC = form.end_time ? new Date(form.end_time).toISOString() : undefined;

      const meeting = await create({
        title: form.title,
        description: form.description || undefined,
        start_time: startTimeRFC,
        end_time: endTimeRFC,
        meeting_type: form.meeting_type,
        participant_ids: [], // MVP 先不实现选用户
      });
      navigate(`/meetings/${meeting.id}`);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="max-w-2xl mx-auto">
      {/* 返回 */}
      <button
        className="btn-ghost mb-4 text-slate-500"
        onClick={() => navigate(-1)}
      >
        <ArrowLeft className="w-4 h-4" />
        返回
      </button>

      <div className="card p-8">
        <h2 className="page-title mb-1">创建新会议</h2>
        <p className="text-sm text-slate-500 mb-6">填写会议信息，稍后可邀请学员加入</p>

        {error && (
          <div className="mb-4 px-3 py-2 rounded-lg bg-red-50 border border-red-200 text-sm text-red-700">
            {error}
          </div>
        )}

        <form onSubmit={onSubmit} className="space-y-5">
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1.5">会议主题 *</label>
            <input
              type="text"
              className="input"
              placeholder="例如：高等数学 — 导数专题辅导"
              value={form.title}
              onChange={(e) => setForm({ ...form, title: e.target.value })}
              required
              maxLength={200}
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1.5">会议类型</label>
            <div className="grid grid-cols-3 gap-3">
              {MEETING_TYPES.map((t) => (
                <button
                  key={t.value}
                  type="button"
                  onClick={() => setForm({ ...form, meeting_type: t.value })}
                  className={`p-3 rounded-lg border text-left transition ${
                    form.meeting_type === t.value
                      ? 'border-brand-500 bg-brand-50'
                      : 'border-slate-200 bg-white hover:border-slate-300'
                  }`}
                >
                  <div className="text-sm font-medium text-slate-800">{t.label}</div>
                  <div className="text-xs text-slate-500 mt-0.5">{t.desc}</div>
                </button>
              ))}
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1.5">开始时间 *</label>
              <input
                type="datetime-local"
                className="input"
                value={form.start_time}
                onChange={(e) => setForm({ ...form, start_time: e.target.value })}
                required
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1.5">结束时间（可选）</label>
              <input
                type="datetime-local"
                className="input"
                value={form.end_time}
                onChange={(e) => setForm({ ...form, end_time: e.target.value })}
              />
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1.5">会议描述</label>
            <textarea
              className="input min-h-[100px]"
              placeholder="简要说明会议内容、需要的准备材料等"
              value={form.description}
              onChange={(e) => setForm({ ...form, description: e.target.value })}
              rows={3}
            />
          </div>

          <div className="flex items-center justify-between pt-4 border-t border-slate-100">
            <div className="flex items-center gap-2 text-sm text-slate-500">
              <Users className="w-4 h-4" />
              <span>创建后可在详情页邀请学员</span>
            </div>
            <div className="flex gap-3">
              <button
                type="button"
                className="btn-secondary"
                onClick={() => navigate(-1)}
              >
                取消
              </button>
              <button type="submit" className="btn-primary" disabled={loading}>
                {loading ? '创建中...' : '创建会议'}
              </button>
            </div>
          </div>
        </form>
      </div>
    </div>
  );
}

// 会议详情页：Tab 切换参会人员/录制回放/会议材料；支持组织者邀请与会后删除
import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import {
  ArrowLeft, Video, CalendarDays, Clock, User, Users, Plus, Trash2,
  AlertTriangle, Film, FileText, Download,
} from 'lucide-react';
import * as meetingApi from '@/api/meeting';
import { useAuthStore } from '@/store/authStore';
import InviteDialog from '@/components/Invite/InviteDialog';
import type { Meeting, Recording, Material } from '@/types';

// 详情页 Tab 标识
type TabKey = 'participants' | 'recordings' | 'materials';

/** 字节数格式化为可读大小（1.2 MB） */
function formatSize(bytes?: number): string {
  if (!bytes || bytes <= 0) return '-';
  const units = ['B', 'KB', 'MB', 'GB'];
  let value = bytes;
  let i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return `${value.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

/** 秒数格式化为时长（mm:ss 或 h:mm:ss） */
function formatDuration(sec?: number): string {
  if (!sec || sec <= 0) return '-';
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = Math.floor(sec % 60);
  const mm = String(m).padStart(2, '0');
  const ss = String(s).padStart(2, '0');
  return h > 0 ? `${h}:${mm}:${ss}` : `${m}:${ss}`;
}

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

export default function MeetingDetail() {
  const navigate = useNavigate();
  const { id } = useParams<{ id: string }>();
  const currentUser = useAuthStore((s) => s.user);
  const [meeting, setMeeting] = useState<Meeting | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [inviteOpen, setInviteOpen] = useState(false);
  // Tab 与录制/材料数据
  const [activeTab, setActiveTab] = useState<TabKey>('participants');
  const [recordings, setRecordings] = useState<Recording[]>([]);
  const [materials, setMaterials] = useState<Material[]>([]);
  const [tabLoading, setTabLoading] = useState(false);
  const [tabError, setTabError] = useState<string | null>(null);
  // 删除会议相关状态
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  const reload = async () => {
    if (!id) return;
    try {
      const resp = await meetingApi.getMeeting(id);
      setMeeting(resp.data!);
    } catch (e) {
      setError((e as Error).message);
    }
  };

  // 组件首次挂载或 id 变化时加载会议详情
  useEffect(() => {
    reload();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  // 切换到「录制回放 / 会议材料」时按需加载对应数据
  useEffect(() => {
    if (!id || activeTab === 'participants') return;
    let cancelled = false;
    setTabLoading(true);
    setTabError(null);

    (async () => {
      try {
        if (activeTab === 'recordings') {
          const resp = await meetingApi.listRecordings(id);
          if (!cancelled) setRecordings(resp.data ?? []);
        } else {
          const resp = await meetingApi.listMaterials(id);
          if (!cancelled) setMaterials(resp.data ?? []);
        }
      } catch (e) {
        if (!cancelled) setTabError((e as Error).message);
      } finally {
        if (!cancelled) setTabLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [activeTab, id]);

  // ⚠️ Hooks 必须在任何条件 return 之前无条件执行
  // 排除已在会中的用户 ID 集合（meeting 为 null 时返回空 Set，不影响下游）
  const participantIDs = useMemo(
    () => new Set((meeting?.participants ?? []).map((p) => p.user_id)),
    [meeting?.participants],
  );

  if (!meeting) {
    return (
      <div className="p-12 text-center">
        {error ? (
          <div className="card p-8">
            <p className="text-red-500 mb-4">{error}</p>
            <button className="btn-secondary" onClick={() => navigate('/meetings')}>返回列表</button>
          </div>
        ) : (
          <div className="text-slate-400">加载中...</div>
        )}
      </div>
    );
  }

  const canJoin = meeting.status === 'scheduled' || meeting.status === 'in_progress';
  // 仅组织者可邀请新参会者
  const isOrganizer = currentUser?.id === meeting.organizer_id;
  const isAdmin = currentUser?.role === 'admin';
  // 会议是否已结束（已结束/已取消，或已过结束时间）——结束后才允许彻底删除
  const hasEnded =
    meeting.status === 'completed' ||
    meeting.status === 'cancelled' ||
    (!!meeting.end_time && new Date(meeting.end_time).getTime() < Date.now());
  // 组织者/管理员可见删除入口；未结束时点击会提示，实际删除由后端二次校验
  const canManage = isOrganizer || isAdmin;

  /** 彻底删除会议（含录制视频与材料），成功后返回列表页 */
  const handlePurge = async () => {
    setDeleting(true);
    setDeleteError(null);
    try {
      await meetingApi.purgeMeeting(meeting.id);
      navigate('/meetings');
    } catch (e) {
      setDeleteError((e as Error).message);
    } finally {
      setDeleting(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* 返回 + 标题区 */}
      <div>
        <button className="btn-ghost text-slate-500 mb-3" onClick={() => navigate('/meetings')}>
          <ArrowLeft className="w-4 h-4" />
          返回列表
        </button>
        <div className="card p-6">
          <div className="flex items-start justify-between">
            <div className="flex-1">
              <div className="flex items-center gap-3 mb-2">
                <h1 className="text-2xl font-semibold text-slate-800">{meeting.title}</h1>
                <StatusBadge status={meeting.status} />
              </div>
              {meeting.description && <p className="text-slate-600 mt-2">{meeting.description}</p>}
              <div className="flex items-center gap-5 mt-4 text-sm text-slate-500">
                <span className="flex items-center gap-1.5"><CalendarDays className="w-4 h-4" />{new Date(meeting.start_time).toLocaleString('zh-CN')}</span>
                {meeting.end_time && (
                  <span className="flex items-center gap-1.5"><Clock className="w-4 h-4" />~ {new Date(meeting.end_time).toLocaleString('zh-CN')}</span>
                )}
                <span className="flex items-center gap-1.5"><User className="w-4 h-4" />{meeting.organizer?.name || '-'}</span>
              </div>
            </div>
            <div className="flex items-center gap-2">
              {canJoin && (
                <button className="btn-primary" onClick={() => navigate(`/room/${meeting.id}`)}>
                  <Video className="w-4 h-4" />
                  {meeting.status === 'in_progress' ? '进入会议' : '开始会议'}
                </button>
              )}
              {/* 组织者/管理员：会后可彻底删除（同时删除录制与材料） */}
              {canManage && (
                <button
                  className="btn-ghost text-sm text-red-600 hover:bg-red-50"
                  onClick={() => { setDeleteError(null); setDeleteOpen(true); }}
                >
                  <Trash2 className="w-4 h-4" />
                  删除会议
                </button>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Tab 区 */}
      <div className="card">
        <div className="px-6 py-4 border-b border-slate-100 flex items-center gap-1">
          <button
            className={`px-3 py-1.5 rounded-lg text-sm font-medium flex items-center gap-2 ${
              activeTab === 'participants' ? 'bg-slate-100 text-slate-800' : 'text-slate-500 hover:text-slate-700 hover:bg-slate-50'
            }`}
            onClick={() => setActiveTab('participants')}
          >
            <Users className="w-4 h-4" />参会人员 ({meeting.participants?.length || 0})
          </button>
          <button
            className={`px-3 py-1.5 rounded-lg text-sm font-medium flex items-center gap-2 ${
              activeTab === 'recordings' ? 'bg-slate-100 text-slate-800' : 'text-slate-500 hover:text-slate-700 hover:bg-slate-50'
            }`}
            onClick={() => setActiveTab('recordings')}
          >
            <Film className="w-4 h-4" />录制回放
          </button>
          <button
            className={`px-3 py-1.5 rounded-lg text-sm font-medium flex items-center gap-2 ${
              activeTab === 'materials' ? 'bg-slate-100 text-slate-800' : 'text-slate-500 hover:text-slate-700 hover:bg-slate-50'
            }`}
            onClick={() => setActiveTab('materials')}
          >
            <FileText className="w-4 h-4" />会议材料
          </button>

          {/* 组织者专属：邀请按钮 */}
          {isOrganizer && (
            <button className="ml-auto btn-ghost text-sm text-brand-600 hover:bg-brand-50" onClick={() => setInviteOpen(true)}>
              <Plus className="w-4 h-4" />
              邀请参会者
            </button>
          )}
        </div>

        <div className="p-6">
          {/* 参会人员 */}
          {activeTab === 'participants' && (
            !meeting.participants || meeting.participants.length === 0 ? (
              <div className="text-center text-slate-400 py-8">暂无参会人员</div>
            ) : (
              <ul className="space-y-3">
                {meeting.participants.map((p) => (
                  <li key={p.id} className="flex items-center gap-3 p-3 rounded-lg border border-slate-100">
                    <div className="w-9 h-9 rounded-full bg-brand-50 flex items-center justify-center text-brand-600 text-sm font-medium">
                      {p.user?.name?.[0] || '?'}
                    </div>
                    <div className="flex-1">
                      <div className="text-sm font-medium text-slate-800">{p.user?.name || '未知用户'}</div>
                      <div className="text-xs text-slate-500">{p.user?.email}</div>
                    </div>
                    <div className="text-xs text-slate-500">
                      {p.participant_role === 'host' ? '主持人' : p.participant_role === 'speaker' ? '主讲人' : '参会者'}
                    </div>
                  </li>
                ))}
              </ul>
            )
          )}

          {/* 录制回放 */}
          {activeTab === 'recordings' && (
            tabLoading ? (
              <div className="text-center text-slate-400 py-8">加载中...</div>
            ) : tabError ? (
              <div className="text-center text-red-500 py-8">{tabError}</div>
            ) : recordings.length === 0 ? (
              <div className="text-center text-slate-400 py-8">暂无录制回放</div>
            ) : (
              <ul className="space-y-3">
                {recordings.map((r) => (
                  <li key={r.id} className="flex items-center gap-3 p-3 rounded-lg border border-slate-100">
                    <div className="w-9 h-9 rounded-lg bg-brand-50 flex items-center justify-center">
                      <Film className="w-4 h-4 text-brand-600" />
                    </div>
                    <div className="flex-1">
                      <div className="text-sm font-medium text-slate-800">
                        录制回放 {r.created_at ? `· ${new Date(r.created_at).toLocaleString('zh-CN')}` : ''}
                      </div>
                      <div className="text-xs text-slate-500">
                        时长 {formatDuration(r.duration_sec)} · 大小 {formatSize(r.file_size_bytes)}
                      </div>
                    </div>
                    {r.file_url ? (
                      <a className="btn-ghost text-sm text-brand-600" href={r.file_url} target="_blank" rel="noreferrer">
                        <Download className="w-4 h-4" />播放/下载
                      </a>
                    ) : (
                      <span className="text-xs text-slate-400">{r.status === 'recording' ? '录制中' : '处理中'}</span>
                    )}
                  </li>
                ))}
              </ul>
            )
          )}

          {/* 会议材料 */}
          {activeTab === 'materials' && (
            tabLoading ? (
              <div className="text-center text-slate-400 py-8">加载中...</div>
            ) : tabError ? (
              <div className="text-center text-red-500 py-8">{tabError}</div>
            ) : materials.length === 0 ? (
              <div className="text-center text-slate-400 py-8">暂无会议材料</div>
            ) : (
              <ul className="space-y-3">
                {materials.map((m) => (
                  <li key={m.id} className="flex items-center gap-3 p-3 rounded-lg border border-slate-100">
                    <div className="w-9 h-9 rounded-lg bg-brand-50 flex items-center justify-center">
                      <FileText className="w-4 h-4 text-brand-600" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="text-sm font-medium text-slate-800 truncate">{m.file_name}</div>
                      <div className="text-xs text-slate-500">
                        {formatSize(m.file_size)} · {new Date(m.created_at).toLocaleString('zh-CN')}
                      </div>
                    </div>
                    <a className="btn-ghost text-sm text-brand-600" href={m.file_url} download={m.file_name}>
                      <Download className="w-4 h-4" />下载
                    </a>
                  </li>
                ))}
              </ul>
            )
          )}
        </div>
      </div>

      {inviteOpen && (
        <InviteDialog
          meetingID={meeting.id}
          excludeIDs={participantIDs}
          onClose={() => setInviteOpen(false)}
          onInvited={() => { setInviteOpen(false); reload(); }}
        />
      )}

      {/* 彻底删除确认弹窗 */}
      {deleteOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="card w-full max-w-md p-6">
            <div className="flex items-start gap-3">
              <div className="w-10 h-10 rounded-full bg-red-50 flex items-center justify-center shrink-0">
                <AlertTriangle className="w-5 h-5 text-red-500" />
              </div>
              <div className="flex-1">
                <h3 className="text-lg font-semibold text-slate-800">删除会议</h3>
                <p className="text-sm text-slate-600 mt-2">
                  确定要彻底删除会议
                  <span className="font-medium text-slate-800">「{meeting.title}」</span>
                  吗？该会议下的<span className="font-medium">录制视频</span>与
                  <span className="font-medium">全部会议材料</span>会被一并永久删除，且无法恢复。
                </p>
                {!hasEnded && (
                  <p className="text-sm text-amber-600 mt-3">
                    会议尚未结束，需等会议结束后才能删除。
                  </p>
                )}
                {deleteError && <p className="text-sm text-red-500 mt-3">{deleteError}</p>}
              </div>
            </div>
            <div className="flex justify-end gap-2 mt-6">
              <button className="btn-secondary" onClick={() => setDeleteOpen(false)} disabled={deleting}>
                取消
              </button>
              <button className="btn-danger" onClick={handlePurge} disabled={deleting || !hasEnded}>
                {deleting ? '删除中...' : '确认删除'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

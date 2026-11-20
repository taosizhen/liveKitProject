// 会议室页面 — 自定义布局：主舞台 + 标注层 + 侧栏（聊天/材料/成员）+ 底部工具栏
// 功能：音视频控制、屏幕共享（LiveKit ScreenShare）、实时标注（静态/激光/白板）、录制合成（水印+时间戳）
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import {
  LiveKitRoom,
  RoomAudioRenderer,
  VideoTrack,
  useLocalParticipant,
  useParticipants,
  useRoomContext,
  useTracks,
} from '@livekit/components-react';
import '@livekit/components-styles';
import { Track } from 'livekit-client';
import {
  FileText, Loader2, MessageSquare, Mic, MicOff, MonitorOff, MonitorUp, PenTool,
  PhoneOff, Square, Users, Video, VideoOff, XCircle,
} from 'lucide-react';
import * as meetingApi from '@/api/meeting';
import { useAuthStore } from '@/store/authStore';
import AnnotationLayer, { type AnnotationLayerHandle } from '@/components/Room/AnnotationLayer';
import ChatPanel from '@/components/Chat/ChatPanel';
import MaterialPanel from '@/components/Materials/MaterialPanel';
import useRoomRecorder from '@/hooks/useRoomRecorder';
import type { LiveKitJoinInfo, Material, Meeting } from '@/types';

/**
 * LiveKit 配置（后端未下发时兜底）
 * HTTPS 页面必须走 wss，且 LiveKit 原生不支持信令端口 TLS，故 HTTPS 下连 7891（TLS 终止代理）
 */
const LIVEKIT_PROTO = window.location.protocol === 'https:' ? 'wss' : 'ws';
const LIVEKIT_URL = `${LIVEKIT_PROTO}://${window.location.hostname}:${LIVEKIT_PROTO === 'wss' ? 7891 : 7890}`;

/** 秒数格式化为 mm:ss / HH:mm:ss */
function formatClock(totalSec: number): string {
  const s = Math.max(0, Math.floor(totalSec));
  const hh = Math.floor(s / 3600);
  const mm = String(Math.floor((s % 3600) / 60)).padStart(2, '0');
  const ss = String(s % 60).padStart(2, '0');
  return hh > 0 ? `${hh}:${mm}:${ss}` : `${mm}:${ss}`;
}

export default function Room() {
  const navigate = useNavigate();
  const { id } = useParams<{ id: string }>();

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [joinInfo, setJoinInfo] = useState<LiveKitJoinInfo | null>(null);
  const [meeting, setMeeting] = useState<Meeting | null>(null);

  const joinedRef = useRef(false);

  /** 获取 LiveKit 入会 Token 与会议信息（只请求一次） */
  useEffect(() => {
    if (!id || joinedRef.current) return;
    joinedRef.current = true;

    (async () => {
      try {
        setLoading(true);
        const [joinResp, meetingResp] = await Promise.all([
          meetingApi.getLiveKitJoinInfo(id),
          meetingApi.getMeeting(id).catch(() => null),
        ]);
        const info = joinResp.data!;
        // 优先用后端返回的 livekit_url，未配置则用本地默认
        setJoinInfo({ ...info, livekit_url: info.livekit_url || LIVEKIT_URL });
        if (meetingResp?.data) setMeeting(meetingResp.data);
      } catch (e) {
        setError((e as Error).message);
      } finally {
        setLoading(false);
      }
    })();
  }, [id]);

  /** 离开会议：返回工作台 */
  const handleLeave = useCallback(() => {
    navigate('/dashboard');
  }, [navigate]);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-900 text-white">
        <div className="text-center">
          <div className="w-10 h-10 border-4 border-white/20 border-t-white rounded-full animate-spin mx-auto mb-4" />
          <p className="text-slate-300">正在连接会议...</p>
        </div>
      </div>
    );
  }

  if (error || !joinInfo) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-50 p-6">
        <div className="card p-8 text-center max-w-md">
          <XCircle className="w-12 h-12 mx-auto mb-3 text-red-500" />
          <h3 className="text-lg font-semibold text-slate-800 mb-2">无法进入会议</h3>
          <p className="text-sm text-slate-500 mb-4">{error || '连接失败'}</p>
          <button className="btn-secondary" onClick={handleLeave}>返回工作台</button>
        </div>
      </div>
    );
  }

  return (
    <LiveKitRoom
      audio
      connect
      serverUrl={joinInfo.livekit_url}
      token={joinInfo.token}
      data-lk-theme="default"
      onConnected={() => console.log('[LiveKit] connected to room:', joinInfo.room_name)}
      onDisconnected={() => {
        console.log('[LiveKit] disconnected');
        handleLeave();
      }}
      onError={(e) => {
        console.error('[LiveKit] error:', e);
        setError(e.message || '连接错误');
      }}
      style={{ height: '100vh', backgroundColor: '#0f172a' }}
    >
      <RoomContent
        meetingID={id ?? ''}
        meetingTitle={meeting?.title ?? '在线会议'}
        roomName={joinInfo.room_name}
        onLeave={handleLeave}
      />
      {/* 房间内远端音频渲染器 */}
      <RoomAudioRenderer />
    </LiveKitRoom>
  );
}

interface RoomContentProps {
  meetingID: string;
  meetingTitle: string;
  roomName: string;
  onLeave: () => void;
}

type SideTab = 'chat' | 'materials' | 'members';

/** 会议室内核：舞台、标注层、侧栏、工具栏 */
function RoomContent({ meetingID, meetingTitle, roomName, onLeave }: RoomContentProps) {
  const room = useRoomContext();
  const userName = useAuthStore((s) => s.user?.name ?? '');
  const { localParticipant, isMicrophoneEnabled, isCameraEnabled, isScreenShareEnabled } = useLocalParticipant();
  const participants = useParticipants();

  const videoRef = useRef<HTMLVideoElement>(null);
  const annotationRef = useRef<AnnotationLayerHandle>(null);

  const [annotating, setAnnotating] = useState(false);
  const [tab, setTab] = useState<SideTab>('members');
  const [materials, setMaterials] = useState<Material[]>([]);
  const [sideError, setSideError] = useState<string | null>(null);

  const tracks = useTracks([Track.Source.Camera, Track.Source.ScreenShare], { onlySubscribed: false });
  const screenShareTrack = tracks.find((t) => t.source === Track.Source.ScreenShare);
  const localCameraTrack = tracks.find((t) => t.source === Track.Source.Camera && t.participant.isLocal);
  const remoteCameraTrack = tracks.find((t) => t.source === Track.Source.Camera && !t.participant.isLocal);
  /** 主画面优先级：屏幕共享 > 远端摄像头 > 本地摄像头 */
  const activeTrack = screenShareTrack ?? remoteCameraTrack ?? localCameraTrack;
  const cameraTracks = useMemo(() => tracks.filter((t) => t.source === Track.Source.Camera), [tracks]);

  /** 提供给录制的取画面/取标注回调 */
  const getVideoElement = useCallback(() => videoRef.current, []);
  const getAnnotationCanvas = useCallback(() => annotationRef.current?.getCanvas() ?? null, []);

  const recorder = useRoomRecorder({
    meetingID,
    meetingTitle,
    userName,
    getVideoElement,
    getAnnotationCanvas,
  });

  /** 加载会议材料 */
  const loadMaterials = useCallback(async () => {
    if (!meetingID) return;
    try {
      const resp = await meetingApi.listMaterials(meetingID);
      setMaterials(resp.data ?? []);
    } catch (e) {
      setSideError((e as Error).message);
    }
  }, [meetingID]);

  useEffect(() => {
    void loadMaterials();
  }, [loadMaterials]);

  /** 上传材料并刷新列表 */
  const handleUploadMaterial = useCallback(async (file: File) => {
    try {
      await meetingApi.uploadMaterial(meetingID, file);
      await loadMaterials();
    } catch (e) {
      setSideError((e as Error).message);
    }
  }, [meetingID, loadMaterials]);

  /** 删除材料并刷新列表 */
  const handleDeleteMaterial = useCallback(async (materialID: string) => {
    try {
      await meetingApi.deleteMaterial(materialID);
      await loadMaterials();
    } catch (e) {
      setSideError((e as Error).message);
    }
  }, [loadMaterials]);

  /** 切换麦克风 */
  const toggleMic = async () => {
    try {
      await localParticipant.setMicrophoneEnabled(!isMicrophoneEnabled);
    } catch (e) {
      setSideError((e as Error).message);
    }
  };

  /** 切换摄像头 */
  const toggleCamera = async () => {
    try {
      await localParticipant.setCameraEnabled(!isCameraEnabled);
    } catch (e) {
      setSideError((e as Error).message);
    }
  };

  /** 切换屏幕共享（LiveKit 原生 ScreenShare） */
  const toggleScreenShare = async () => {
    try {
      await localParticipant.setScreenShareEnabled(!isScreenShareEnabled);
    } catch (e) {
      // 用户主动取消选择屏幕时会抛错，忽略即可
      const msg = (e as Error).message;
      if (!/permission|denied|cancel/i.test(msg)) setSideError(msg);
    }
  };

  /** 离开会议：录制中先停止并上传 */
  const handleLeave = async () => {
    if (recorder.recording) await recorder.stop();
    room.disconnect();
    onLeave();
  };

  const toolBtnBase = 'flex flex-col items-center justify-center gap-1 w-16 h-14 rounded-xl transition text-xs';

  /** 底部工具按钮 */
  const ToolButton = ({
    onClick, active, danger, label, icon,
  }: { onClick: () => void; active?: boolean; danger?: boolean; label: string; icon: React.ReactNode }) => (
    <button
      type="button"
      onClick={onClick}
      className={`${toolBtnBase} ${
        danger
          ? 'bg-red-500/90 hover:bg-red-500 text-white'
          : active
            ? 'bg-white/15 text-white'
            : 'text-white/75 hover:bg-white/10'
      }`}
    >
      {icon}
      <span className="leading-none">{label}</span>
    </button>
  );

  return (
    <div className="h-screen flex flex-col bg-slate-950 text-white overflow-hidden">
      {/* 顶部信息栏 */}
      <header className="h-14 shrink-0 px-4 flex items-center gap-3 border-b border-white/10">
        <div className="min-w-0">
          <div className="font-medium truncate">{meetingTitle}</div>
          <div className="text-[11px] text-white/40 truncate">{roomName}</div>
        </div>

        <div className="ml-auto flex items-center gap-4 text-xs">
          {recorder.recording && (
            <span className="flex items-center gap-1.5 text-red-400">
              <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse" />
              录制中 {formatClock(recorder.elapsed)}
            </span>
          )}
          {recorder.saving && <span className="flex items-center gap-1 text-amber-300"><Loader2 className="w-3.5 h-3.5 animate-spin" />上传中</span>}
          <span className="flex items-center gap-1 text-white/60">
            <Users className="w-4 h-4" />{participants.length}
          </span>
        </div>
      </header>

      {/* 主体：舞台 + 侧栏 */}
      <div className="flex-1 min-h-0 flex">
        <div className="flex-1 min-w-0 relative bg-black">
          {activeTrack ? (
            <VideoTrack
              ref={videoRef}
              trackRef={activeTrack}
              className="w-full h-full object-contain"
            />
          ) : (
            <div className="absolute inset-0 flex flex-col items-center justify-center text-white/40 gap-2">
              <VideoOff className="w-10 h-10" />
              <p className="text-sm">暂无视频画面，可开启摄像头或共享屏幕</p>
            </div>
          )}

          {/* 自身画面小窗（主画面不是本地摄像头时展示） */}
          {localCameraTrack && activeTrack !== localCameraTrack && (
            <div className="absolute bottom-3 right-3 w-44 aspect-video rounded-lg overflow-hidden border border-white/20 bg-black shadow-lg z-10">
              <VideoTrack trackRef={localCameraTrack} className="w-full h-full object-cover" />
            </div>
          )}

          {/* 标注层（静态标记 / 激光笔 / 白板，含画布） */}
          <AnnotationLayer ref={annotationRef} enabled={annotating} onExit={() => setAnnotating(false)} />
        </div>

        {/* 右侧栏 */}
        <aside className="w-80 shrink-0 flex flex-col bg-white text-slate-700 border-l border-slate-200">
          <div className="flex border-b border-slate-200">
            {([
              ['members', '成员', Users],
              ['chat', '聊天', MessageSquare],
              ['materials', '材料', FileText],
            ] as Array<[SideTab, string, typeof Users]>).map(([key, label, Icon]) => (
              <button
                key={key}
                onClick={() => setTab(key)}
                className={`flex-1 py-2.5 text-sm flex items-center justify-center gap-1.5 border-b-2 transition ${
                  tab === key ? 'border-brand-600 text-brand-600 font-medium' : 'border-transparent text-slate-500 hover:text-slate-700'
                }`}
              >
                <Icon className="w-4 h-4" />{label}
              </button>
            ))}
          </div>

          <div className="flex-1 min-h-0 overflow-hidden p-2">
            {tab === 'members' && (
              <div className="h-full overflow-y-auto space-y-2">
                {cameraTracks.length === 0 && (
                  <p className="text-center text-sm text-slate-400 py-8">暂无成员画面</p>
                )}
                {cameraTracks.map((t) => (
                  <div key={`${t.participant.identity}-${t.source}`} className="relative rounded-lg overflow-hidden bg-slate-900">
                    <VideoTrack trackRef={t} className="w-full aspect-video object-cover" />
                    <span className="absolute left-2 bottom-1.5 text-[11px] px-1.5 py-0.5 rounded bg-black/50 text-white">
                      {t.participant.name || t.participant.identity}{t.participant.isLocal ? '（我）' : ''}
                    </span>
                  </div>
                ))}
                {/* 无摄像头的成员也列出来 */}
                {participants
                  .filter((p) => !cameraTracks.some((t) => t.participant.identity === p.identity))
                  .map((p) => (
                    <div key={p.identity} className="flex items-center gap-2 px-2 py-2 rounded-lg bg-slate-50 text-sm">
                      <span className="w-6 h-6 rounded-full bg-brand-100 text-brand-700 text-xs flex items-center justify-center">
                        {(p.name || p.identity).slice(0, 1)}
                      </span>
                      <span className="truncate">{p.name || p.identity}{p.isLocal ? '（我）' : ''}</span>
                    </div>
                  ))}
              </div>
            )}

            {tab === 'chat' && <ChatPanel meetingID={meetingID} className="h-full" />}

            {tab === 'materials' && (
              <div className="h-full overflow-y-auto">
                <MaterialPanel
                  meetingID={meetingID}
                  materials={materials}
                  onUpload={handleUploadMaterial}
                  onDelete={handleDeleteMaterial}
                />
              </div>
            )}
          </div>

          {(sideError || recorder.error) && (
            <div className="px-3 py-2 text-xs text-red-600 bg-red-50 border-t border-red-100 flex items-start gap-1">
              <XCircle className="w-3.5 h-3.5 mt-0.5 shrink-0" />
              <span className="break-all">{sideError || recorder.error}</span>
            </div>
          )}
        </aside>
      </div>

      {/* 底部工具栏 */}
      <footer className="h-20 shrink-0 flex items-center justify-center gap-2 border-t border-white/10">
        <ToolButton
          onClick={toggleMic}
          active={!isMicrophoneEnabled}
          label={isMicrophoneEnabled ? '静音' : '取消静音'}
          icon={isMicrophoneEnabled ? <Mic className="w-5 h-5" /> : <MicOff className="w-5 h-5 text-red-400" />}
        />
        <ToolButton
          onClick={toggleCamera}
          active={!isCameraEnabled}
          label={isCameraEnabled ? '关摄像头' : '开摄像头'}
          icon={isCameraEnabled ? <Video className="w-5 h-5" /> : <VideoOff className="w-5 h-5 text-red-400" />}
        />
        <ToolButton
          onClick={toggleScreenShare}
          active={isScreenShareEnabled}
          label={isScreenShareEnabled ? '停止共享' : '屏幕共享'}
          icon={isScreenShareEnabled ? <MonitorOff className="w-5 h-5 text-brand-400" /> : <MonitorUp className="w-5 h-5" />}
        />
        <ToolButton
          onClick={() => setAnnotating((v) => !v)}
          active={annotating}
          label={annotating ? '退出标注' : '标注'}
          icon={<PenTool className={`w-5 h-5 ${annotating ? 'text-brand-400' : ''}`} />}
        />
        <ToolButton
          onClick={() => { void (recorder.recording ? recorder.stop() : recorder.start()); }}
          active={recorder.recording}
          danger={recorder.recording}
          label={recorder.recording ? '停止录制' : '录制'}
          icon={recorder.saving
            ? <Loader2 className="w-5 h-5 animate-spin" />
            : recorder.recording
              ? <Square className="w-5 h-5" />
              : <span className="w-5 h-5 rounded-full border-2 border-current" />}
        />
        <ToolButton
          onClick={() => { void handleLeave(); }}
          danger
          label="离开"
          icon={<PhoneOff className="w-5 h-5" />}
        />
      </footer>
    </div>
  );
}

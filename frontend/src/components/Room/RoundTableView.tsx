// 同框圆桌视图：全员席位沿圆桌圆周均布（圆形头像/视频，不抠图）
// 席位规则：angle=-90°+i×360°/N，left/top=50%+38%×cos/sin（相对内部正方形容器）
// 发言人描边发光、主持人皇冠徽标、举手标记、麦克风状态角标
import { useMemo } from 'react';
import { useParticipants, useTracks, VideoTrack } from '@livekit/components-react';
import { Track, type Participant } from 'livekit-client';
import { Crown, Hand, Mic, MicOff } from 'lucide-react';
import { computeHostIdentity, parseParticipantMeta } from '@/hooks/useDynamicHost';
import { useSignalStore } from '@/store/signalStore';

/** 圆桌桌面背景：纯 CSS 径向渐变模拟深色木质桌面，避免外链图片在无外网环境下加载失败 */
const ROUND_TABLE_BG_STYLE: React.CSSProperties = {
  background:
    'radial-gradient(circle at 50% 45%, #3d2d1e 0%, #241810 45%, #120b07 78%, #070402 100%)',
  boxShadow: 'inset 0 0 60px rgba(0,0,0,0.7), inset 0 0 120px rgba(0,0,0,0.4)',
};

interface RoundTableViewProps {
  /** full=铺满舞台；mini=小地图（点击展开） */
  size?: 'full' | 'mini';
  /** 当前发言人 identity（高亮描边） */
  activeSpeakerId?: string | null;
  /** mini 态点击回调（放大为全屏） */
  onExpand?: () => void;
}

/** 按人数计算席位直径（px）：人越多越小 */
function seatSize(count: number, mini: boolean): number {
  if (mini) return count <= 8 ? 30 : 24;
  if (count <= 6) return 96;
  if (count <= 12) return 72;
  return 56;
}

/** 同框圆桌视图 */
export default function RoundTableView({ size = 'full', activeSpeakerId, onExpand }: RoundTableViewProps) {
  const mini = size === 'mini';
  const participants = useParticipants();
  const tracks = useTracks([Track.Source.Camera], { onlySubscribed: false });
  const hands = useSignalStore((s) => s.hands);

  const hostIdentity = useMemo(() => computeHostIdentity(participants), [participants]);

  /** identity → 摄像头 trackRef（有摄像头才有视频席位） */
  const cameraByIdentity = useMemo(() => {
    const map = new Map<string, (typeof tracks)[number]>();
    for (const t of tracks) {
      if (t.source === Track.Source.Camera) map.set(t.participant.identity, t);
    }
    return map;
  }, [tracks]);

  const n = participants.length;
  const seat = seatSize(n, mini);
  const handCount = Object.keys(hands).length;

  /** 单个席位（圆周均布） */
  const renderSeat = (p: Participant, i: number) => {
    const rad = ((-90 + (i * 360) / n) * Math.PI) / 180;
    const left = 50 + 38 * Math.cos(rad);
    const top = 50 + 38 * Math.sin(rad);
    const meta = parseParticipantMeta(p);
    const trackRef = cameraByIdentity.get(p.identity);
    const speaking = activeSpeakerId === p.identity;
    const isHost = hostIdentity === p.identity;
    const handRaised = p.identity in hands;
    const name = p.name || p.identity;

    return (
      <div
        key={p.identity}
        className="absolute flex flex-col items-center"
        style={{ left: `${left}%`, top: `${top}%`, transform: 'translate(-50%, -50%)' }}
      >
        <div
          className={`relative rounded-full overflow-hidden bg-slate-800 ring-2 transition ${
            speaking ? 'ring-green-400 shadow-[0_0_12px_2px_rgba(74,222,128,0.6)]' : 'ring-white/20'
          }`}
          style={{ width: seat, height: seat }}
          title={name}
        >
          {trackRef ? (
            <VideoTrack trackRef={trackRef} className="w-full h-full object-cover" />
          ) : meta.avatarUrl ? (
            <img src={meta.avatarUrl} alt={name} className="w-full h-full object-cover" />
          ) : (
            <span
              className="w-full h-full flex items-center justify-center bg-brand-600 text-white font-medium"
              style={{ fontSize: seat * 0.4 }}
            >
              {name.slice(0, 1)}
            </span>
          )}
          {/* 麦克风状态角标 */}
          {!mini && (
            <span className="absolute bottom-0.5 right-0.5 p-0.5 rounded-full bg-black/60">
              {p.isMicrophoneEnabled ? (
                <Mic className="w-3 h-3 text-green-400" />
              ) : (
                <MicOff className="w-3 h-3 text-red-400" />
              )}
            </span>
          )}
        </div>
        {/* 主持人 / 举手徽标 */}
        {isHost && (
          <span
            className="absolute -top-1 -left-1 p-0.5 rounded-full bg-amber-500 text-white"
            title="主持人"
          >
            <Crown className={mini ? 'w-2.5 h-2.5' : 'w-3 h-3'} />
          </span>
        )}
        {handRaised && (
          <span
            className="absolute -top-1 -right-1 p-0.5 rounded-full bg-amber-400 text-white"
            title="举手中"
          >
            <Hand className={mini ? 'w-2.5 h-2.5' : 'w-3 h-3'} />
          </span>
        )}
        {/* 姓名（mini 态省略） */}
        {!mini && (
          <span className="mt-1 max-w-24 truncate text-[11px] px-1.5 py-0.5 rounded bg-black/50 text-white">
            {name}{p.isLocal ? '（我）' : ''}
          </span>
        )}
      </div>
    );
  };

  return (
    <div
      onClick={mini ? onExpand : undefined}
      className={`relative overflow-hidden bg-slate-950 ${
        mini
          ? 'w-44 h-44 rounded-xl border border-white/20 shadow-xl cursor-pointer hover:border-brand-400 transition'
          : 'w-full h-full'
      }`}
      title={mini ? '点击展开同框圆桌' : undefined}
    >
      {/* 内部正方形区域：保证圆周百分比定位横纵一致 */}
      <div className="absolute inset-0 m-auto aspect-square h-full max-w-full">
        <div
          className="absolute inset-0 w-full h-full"
          style={ROUND_TABLE_BG_STYLE}
        />
        {participants.map(renderSeat)}
      </div>
      {/* 全屏圆桌：举手人数醒目提示（小地图态不显示，避免遮挡） */}
      {!mini && handCount > 0 && (
        <div className="absolute top-2 left-2 z-10 flex items-center gap-1.5 px-3 py-1 rounded-full bg-amber-500/90 text-white text-xs shadow-lg">
          <Hand className="w-3.5 h-3.5" />
          <span>举手 {handCount} 人</span>
        </div>
      )}
      {mini && (
        <span className="absolute bottom-1 left-1/2 -translate-x-1/2 px-1.5 py-0.5 rounded bg-black/60 text-[10px] text-white/80">
          同框圆桌
        </span>
      )}
    </div>
  );
}

// 参会成员列表：视频卡片 + 无摄像头成员行 + 举手列表（主持人点名入口）
// 供侧栏成员页与"同框圆桌"模式下的小地图（compact）复用
import { VideoTrack, type TrackReference } from '@livekit/components-react';
import type { Participant } from 'livekit-client';
import { Crown, Hand, Pin, Volume2 } from 'lucide-react';
import { parseParticipantMeta } from '@/hooks/useDynamicHost';
import type { RaisedHand } from '@/store/signalStore';

interface MembersListProps {
  /** 全部摄像头轨道 */
  cameraTracks: TrackReference[];
  /** 全部参会者（含本地） */
  participants: Participant[];
  /** 举手表：identity → 举手记录 */
  hands: Record<string, RaisedHand>;
  /** 举手列表（已按时间升序） */
  raisedHands: RaisedHand[];
  hostIdentity: string | null;
  activeSpeakerId: string | null;
  pinnedIdentity: string | null;
  /** 自己是否是主持人（决定"邀请发言"按钮显隐） */
  isHost: boolean;
  localIdentity: string;
  /** 小地图模式：更紧凑的排版 */
  compact?: boolean;
  /** 点击成员画面钉住/取消钉住主画面 */
  onTogglePin: (identity: string) => void;
  /** 主持人点名 */
  onDesignate: (identity: string) => void;
}

/** 参会成员列表（圆桌全屏时可作为小地图复用，compact 紧凑排版） */
export default function MembersList({
  cameraTracks,
  participants,
  hands,
  raisedHands,
  hostIdentity,
  activeSpeakerId,
  pinnedIdentity,
  isHost,
  localIdentity,
  compact = false,
  onTogglePin,
  onDesignate,
}: MembersListProps) {
  return (
    <div className={`space-y-2 ${compact ? 'p-1.5' : ''}`}>
      {/* 举手列表（按时间升序），主持人可点名邀请发言 */}
      {raisedHands.length > 0 && (
        <div className="rounded-lg bg-amber-50 border border-amber-200 p-2 space-y-1">
          <div className="flex items-center gap-1 text-xs font-medium text-amber-700 px-1">
            <Hand className="w-3.5 h-3.5" />举手（{raisedHands.length}）
          </div>
          {raisedHands.map((h) => (
            <div key={h.identity} className="flex items-center gap-2 px-1 py-0.5 text-sm">
              <span className="truncate flex-1 text-slate-700">
                {h.name}{h.identity === localIdentity ? '（我）' : ''}
              </span>
              {isHost && h.identity !== localIdentity && (
                <button
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation();
                    onDesignate(h.identity);
                  }}
                  className="shrink-0 px-2 py-0.5 rounded bg-brand-600 text-white text-xs hover:bg-brand-700"
                >
                  邀请发言
                </button>
              )}
            </div>
          ))}
        </div>
      )}

      {cameraTracks.length === 0 && (
        <p className="text-center text-sm text-slate-400 py-8">暂无成员画面</p>
      )}

      {/* 有摄像头的成员：视频卡片 */}
      {cameraTracks.map((t) => {
        const identity = t.participant.identity;
        const speaking = activeSpeakerId === identity;
        const pinned = pinnedIdentity === identity;
        return (
          <div
            key={`${identity}-${t.source}`}
            onClick={(e) => {
              e.stopPropagation();
              onTogglePin(identity);
            }}
            title={pinned ? '取消钉住' : '点击钉住到主画面'}
            className={`relative rounded-lg overflow-hidden bg-slate-900 cursor-pointer ring-2 transition ${
              pinned ? 'ring-brand-400' : speaking ? 'ring-green-400' : 'ring-transparent'
            }`}
          >
            <VideoTrack trackRef={t} className="w-full aspect-video object-cover" />
            <span className="absolute left-2 bottom-1.5 text-[11px] px-1.5 py-0.5 rounded bg-black/50 text-white flex items-center gap-1">
              {t.participant.name || identity}{t.participant.isLocal ? '（我）' : ''}
            </span>
            {/* 主持人徽标 */}
            {hostIdentity === identity && (
              <span className="absolute left-2 top-1.5 p-1 rounded bg-amber-500/90 text-white" title="主持人">
                <Crown className="w-3 h-3" />
              </span>
            )}
            {/* 举手徽标 */}
            {identity in hands && (
              <span className="absolute right-2 bottom-1.5 p-1 rounded bg-amber-500/90 text-white" title="举手中">
                <Hand className="w-3 h-3" />
              </span>
            )}
            {/* 钉住 / 发言中角标 */}
            {pinned && (
              <span className="absolute right-2 top-1.5 p-1 rounded bg-brand-500/90 text-white" title="已钉住">
                <Pin className="w-3 h-3" />
              </span>
            )}
            {!pinned && speaking && (
              <span className="absolute right-2 top-1.5 flex items-center gap-1 px-1.5 py-0.5 rounded bg-green-500/90 text-white text-[10px]">
                <Volume2 className="w-3 h-3" />发言中
              </span>
            )}
          </div>
        );
      })}

      {/* 无摄像头的成员也列出来 */}
      {participants
        .filter((p) => !cameraTracks.some((t) => t.participant.identity === p.identity))
        .map((p) => {
          const meta = parseParticipantMeta(p);
          const speaking = activeSpeakerId === p.identity;
          return (
            <div
              key={p.identity}
              className={`flex items-center gap-2 px-2 ${compact ? 'py-1' : 'py-2'} rounded-lg bg-slate-50 text-sm ring-2 transition ${
                speaking ? 'ring-green-400' : 'ring-transparent'
              }`}
            >
              {meta.avatarUrl ? (
                <img src={meta.avatarUrl} alt="" className="w-6 h-6 rounded-full object-cover" />
              ) : (
                <span className="w-6 h-6 rounded-full bg-brand-100 text-brand-700 text-xs flex items-center justify-center">
                  {(p.name || p.identity).slice(0, 1)}
                </span>
              )}
              <span className="truncate flex-1 text-slate-700">
                {p.name || p.identity}{p.isLocal ? '（我）' : ''}
              </span>
              {p.identity in hands && (
                <Hand className="w-3.5 h-3.5 text-amber-500 shrink-0" />
              )}
              {hostIdentity === p.identity && (
                <Crown className="w-3.5 h-3.5 text-amber-500 shrink-0" />
              )}
              {speaking && <Volume2 className="w-3.5 h-3.5 text-green-500 shrink-0" />}
            </div>
          );
        })}
    </div>
  );
}

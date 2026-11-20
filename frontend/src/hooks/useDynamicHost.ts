// 动态主持人：按确定性规则从房间内 participant 推导主持人（零后端状态）
// 规则：角色权重（admin/teacher=0 < student=1）→ joinedAt 升序 → identity 字典序，取第一
// 自动满足：① 仅学生时最早加入者为主持人；② 老师/管理员进入立即接任；③ 其下线后回到在场最早加入者
import { useEffect, useMemo, useRef } from 'react';
import { useLocalParticipant, useParticipants } from '@livekit/components-react';
import type { Participant } from 'livekit-client';

/** 从 participant.metadata 解析出的扩展信息（后端签 token 时注入） */
export interface ParticipantMeta {
  /** 角色：admin / teacher / student（缺省按 student 处理） */
  role: string;
  /** 头像访问路径（可能为空） */
  avatarUrl: string;
}

/** 解析 participant.metadata（JSON：{"role":"...","avatar_url":"..."}），容错返回默认值 */
export function parseParticipantMeta(p: Participant): ParticipantMeta {
  try {
    const m = p.metadata ? (JSON.parse(p.metadata) as Record<string, unknown>) : {};
    return {
      role: typeof m.role === 'string' && m.role ? m.role : 'student',
      avatarUrl: typeof m.avatar_url === 'string' ? m.avatar_url : '',
    };
  } catch {
    return { role: 'student', avatarUrl: '' };
  }
}

/** 角色权重：老师/管理员优先接任主持人 */
function roleWeight(role: string): number {
  return role === 'admin' || role === 'teacher' ? 0 : 1;
}

/** 计算主持人 identity：排序取第一（跨端算法必须一致） */
export function computeHostIdentity(participants: Participant[]): string | null {
  if (participants.length === 0) return null;
  const sorted = [...participants].sort((a, b) => {
    const wa = roleWeight(parseParticipantMeta(a).role);
    const wb = roleWeight(parseParticipantMeta(b).role);
    if (wa !== wb) return wa - wb;
    const ta = a.joinedAt?.getTime() ?? Number.MAX_SAFE_INTEGER;
    const tb = b.joinedAt?.getTime() ?? Number.MAX_SAFE_INTEGER;
    if (ta !== tb) return ta - tb;
    return a.identity.localeCompare(b.identity);
  });
  return sorted[0].identity;
}

/**
 * 动态主持人 Hook
 * - 实时计算 hostIdentity / isHost
 * - 静音入会约定下，自己「接任主持人」的瞬间自动开麦（仅状态跃迁时触发一次，
 *   不与用户手动静音冲突；被降级后再次接任会重新触发）
 */
export function useDynamicHost() {
  const participants = useParticipants(); // 含本地 participant
  const { localParticipant } = useLocalParticipant();

  const hostIdentity = useMemo(() => computeHostIdentity(participants), [participants]);
  const isHost = hostIdentity !== null && hostIdentity === localParticipant.identity;

  const wasHostRef = useRef(false);
  useEffect(() => {
    if (isHost && !wasHostRef.current) {
      wasHostRef.current = true;
      // 接任主持人 → 自动开麦（首次会触发浏览器麦克风权限框，属预期）
      localParticipant.setMicrophoneEnabled(true).catch(() => {});
    } else if (!isHost) {
      wasHostRef.current = false;
    }
  }, [isHost, localParticipant]);

  return { hostIdentity, isHost };
}

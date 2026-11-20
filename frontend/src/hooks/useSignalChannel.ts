// 举手/点名信令 Hook（topic=`signal`，reliable）
// 协议（JSON 信封，src 固定为 'signal'）：
//   hand_raise     {identity,name,ts}        举手（新加入者同步时也会重发）
//   hand_lower     {identity,by?,ts}         放下手（by=主持人时为点名清除）
//   hand_sync_req  {identity,ts}             新加入者请求同步举手状态
//   designate      {target,by,ts}            主持人点名发言
//   designate_ack  {identity,ok,ts}          被点名端回执（已自动开麦）
import { useCallback, useEffect, useRef } from 'react';
import { RoomEvent, type Room } from 'livekit-client';
import { publishDataMessage, useDataChannel } from '@/hooks/useDataChannel';
import { useSignalStore } from '@/store/signalStore';

const SIGNAL_TOPIC = 'signal';

interface UseSignalChannelOptions {
  room: Room;
  /** 本地 participant identity */
  localIdentity: string;
  /** 本地显示名（用于举手广播） */
  localName: string;
  /** 当前是否为动态主持人（决定是否响应点名请求的发起权限） */
  isHost: boolean;
}

/**
 * 举手/点名信令
 * - 维护本地举手表（事件溯源：hand_raise/hand_lower/hand_sync_req）
 * - 被点名时自动开麦并清除自身举手
 * - 返回举手/放手/点名动作供 UI 调用
 */
export function useSignalChannel({ room, localIdentity, localName, isHost }: UseSignalChannelOptions) {
  const isHostRef = useRef(isHost);
  isHostRef.current = isHost;
  const nameRef = useRef(localName);
  nameRef.current = localName;
  const identityRef = useRef(localIdentity);
  identityRef.current = localIdentity;

  /** 广播信令消息 */
  const post = useCallback(
    (msg: Record<string, unknown>) => publishDataMessage(room, SIGNAL_TOPIC, { src: 'signal', ...msg }),
    [room],
  );

  /** 举手 */
  const raiseHand = useCallback(() => {
    const hand = { identity: identityRef.current, name: nameRef.current, ts: Date.now() };
    useSignalStore.getState().addHand(hand);
    post({ k: 'hand_raise', ...hand });
  }, [post]);

  /** 放下手 */
  const lowerHand = useCallback(() => {
    useSignalStore.getState().removeHand(identityRef.current);
    post({ k: 'hand_lower', identity: identityRef.current, ts: Date.now() });
  }, [post]);

  /** 主持人点名：邀请指定成员发言 */
  const designate = useCallback(
    (target: string) => {
      if (!isHostRef.current) return;
      post({ k: 'designate', target, by: identityRef.current, ts: Date.now() });
    },
    [post],
  );

  /** 收到信令消息：更新本地状态 / 响应对自己的点名 */
  const handleMessage = useCallback(
    (msg: Record<string, unknown>) => {
      if (msg.src !== 'signal') return;
      const store = useSignalStore.getState();
      switch (msg.k) {
        case 'hand_raise': {
          const identity = String(msg.identity ?? '');
          if (!identity) return;
          store.addHand({
            identity,
            name: String(msg.name ?? identity),
            ts: typeof msg.ts === 'number' ? msg.ts : Date.now(),
          });
          break;
        }
        case 'hand_lower': {
          const identity = String(msg.identity ?? '');
          if (identity) store.removeHand(identity);
          break;
        }
        case 'hand_sync_req': {
          // 新加入者请求同步：若自己正举手，重发 hand_raise 让其收敛
          const mine = store.hands[identityRef.current];
          if (mine) post({ k: 'hand_raise', ...mine });
          break;
        }
        case 'designate': {
          // 被点名：自动开麦 → 清除自身举手并广播 → 回执
          if (String(msg.target ?? '') !== identityRef.current) return;
          const by = String(msg.by ?? '');
          const hostName = by || '主持人';
          room.localParticipant
            .setMicrophoneEnabled(true)
            .catch(() => {})
            .finally(() => {
              store.removeHand(identityRef.current);
              post({ k: 'hand_lower', identity: identityRef.current, by, ts: Date.now() });
              post({ k: 'designate_ack', identity: identityRef.current, ok: true, ts: Date.now() });
            });
          store.setDesignateNotice(`「${hostName}」邀请你发言，已为你开启麦克风`);
          window.setTimeout(() => useSignalStore.getState().setDesignateNotice(null), 4000);
          break;
        }
        case 'designate_ack': {
          // 主持人端收到回执提示
          if (!isHostRef.current) return;
          const identity = String(msg.identity ?? '');
          const name = store.hands[identity]?.name ?? identity;
          store.setDesignateAckNotice(`「${name}」已接受发言`);
          window.setTimeout(() => useSignalStore.getState().setDesignateAckNotice(null), 3000);
          break;
        }
        default:
          break;
      }
    },
    [post, room],
  );

  useDataChannel(room, SIGNAL_TOPIC, handleMessage);

  // 进房 ~500ms 后广播同步请求，让举手中者重发 hand_raise 收敛状态
  useEffect(() => {
    const timer = window.setTimeout(() => {
      post({ k: 'hand_sync_req', identity: identityRef.current, ts: Date.now() });
    }, 500);
    return () => window.clearTimeout(timer);
  }, [post]);

  // 成员离开时移除其举手记录
  useEffect(() => {
    const onLeft = (p: { identity: string }) => {
      useSignalStore.getState().removeHand(p.identity);
    };
    room.on(RoomEvent.ParticipantDisconnected, onLeft);
    return () => {
      room.off(RoomEvent.ParticipantDisconnected, onLeft);
    };
  }, [room]);

  // 离开房间（组件卸载）时清空本地举手表
  useEffect(() => () => useSignalStore.getState().clearHands(), []);

  return { raiseHand, lowerHand, designate };
}

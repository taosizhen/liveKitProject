// 通用 Data Channel 订阅 Hook：按 topic 过滤 RoomEvent.DataReceived，统一挂卸
import { useEffect } from 'react';
import { RoomEvent, type RemoteParticipant, type Room } from 'livekit-client';

/** Data Channel 消息回调（已按 topic 过滤、已 JSON 解析） */
export type DataChannelHandler = (
  msg: Record<string, unknown>,
  participant: RemoteParticipant | undefined,
) => void;

/**
 * 订阅指定 topic 的 Data Channel 消息
 * @param room LiveKit Room 实例
 * @param topic 数据主题（annotation / signal / remote_control ...）
 * @param onMessage 收到合法 JSON 消息时的回调
 */
export function useDataChannel(room: Room, topic: string, onMessage: DataChannelHandler) {
  useEffect(() => {
    const onData = (
      payload: Uint8Array,
      participant?: RemoteParticipant,
      _kind?: unknown,
      msgTopic?: string,
    ) => {
      if (msgTopic !== topic) return;
      try {
        const msg = JSON.parse(new TextDecoder().decode(payload)) as Record<string, unknown>;
        onMessage(msg, participant);
      } catch {
        // 非 JSON 消息，忽略
      }
    };
    room.on(RoomEvent.DataReceived, onData);
    return () => {
      room.off(RoomEvent.DataReceived, onData);
    };
  }, [room, topic, onMessage]);
}

/** 向房间内广播指定 topic 的 JSON 消息（reliable 通道） */
export function publishDataMessage(room: Room, topic: string, msg: Record<string, unknown>) {
  try {
    room.localParticipant.publishData(new TextEncoder().encode(JSON.stringify(msg)), {
      reliable: true,
      topic,
    });
  } catch {
    // 数据通道不可用时忽略
  }
}

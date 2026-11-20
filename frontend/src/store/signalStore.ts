// 举手/点名信令状态 Store（纯内存，事件溯源，不落库）
// 新加入者通过 hand_sync_req 广播让举手中者重发 hand_raise 收敛状态
import { create } from 'zustand';

/** 一条举手记录 */
export interface RaisedHand {
  identity: string;
  name: string;
  /** 举手时间戳（毫秒），列表按此升序排列 */
  ts: number;
}

interface SignalState {
  /** 举手中的人员表：identity → 举手记录 */
  hands: Record<string, RaisedHand>;
  /** 被点名提示（被点名端弹出 toast，null 表示无） */
  designateNotice: string | null;
  /** 点名结果提示（主持人端弹出，如"对方已开麦"） */
  designateAckNotice: string | null;

  /** 登记/刷新一条举手 */
  addHand: (hand: RaisedHand) => void;
  /** 移除一条举手（放下手/被点名/离线） */
  removeHand: (identity: string) => void;
  /** 清空全部举手（离开房间时） */
  clearHands: () => void;
  /** 设置被点名提示 */
  setDesignateNotice: (msg: string | null) => void;
  /** 设置点名结果提示 */
  setDesignateAckNotice: (msg: string | null) => void;
}

export const useSignalStore = create<SignalState>()((set) => ({
  hands: {},
  designateNotice: null,
  designateAckNotice: null,

  addHand: (hand) =>
    set((s) => ({ hands: { ...s.hands, [hand.identity]: hand } })),
  removeHand: (identity) =>
    set((s) => {
      if (!(identity in s.hands)) return s;
      const next = { ...s.hands };
      delete next[identity];
      return { hands: next };
    }),
  clearHands: () => set({ hands: {} }),
  setDesignateNotice: (msg) => set({ designateNotice: msg }),
  setDesignateAckNotice: (msg) => set({ designateAckNotice: msg }),
}));

/** 按举手时间升序的选择器（主持人点名按此顺序） */
export function selectRaisedHands(s: SignalState): RaisedHand[] {
  return Object.values(s.hands).sort((a, b) => a.ts - b.ts);
}

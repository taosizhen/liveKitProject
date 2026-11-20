// 远程控制会话状态 Store（纯内存，随房间生命周期存在）
import { create } from 'zustand';

/** 远程控制角色：无 / 请求中 / 控制端 / 被控端 */
export type RcRole = 'none' | 'requesting' | 'controller' | 'controlled';

/** 被控端收到的控制请求 */
export interface RcIncomingRequest {
  from: string;
  name: string;
}

interface RemoteControlState {
  role: RcRole;
  /** 对端 identity */
  peerIdentity: string | null;
  /** 对端显示名 */
  peerName: string | null;
  /** 被控端：待处理的控制请求（弹授权窗） */
  incomingRequest: RcIncomingRequest | null;
  /** 一次性提示（toast） */
  notice: string | null;
  /** 被控端：本地代理不可用（引导下载/启动） */
  agentMissing: boolean;

  /** 进入指定角色 */
  setRole: (role: RcRole, peer?: { identity: string; name: string } | null) => void;
  /** 设置待处理请求 */
  setIncomingRequest: (req: RcIncomingRequest | null) => void;
  /** 设置一次性提示 */
  setNotice: (msg: string | null) => void;
  /** 标记本地代理缺失 */
  setAgentMissing: (v: boolean) => void;
  /** 复位全部状态（离开房间/会话结束） */
  reset: () => void;
}

export const useRemoteControlStore = create<RemoteControlState>()((set) => ({
  role: 'none',
  peerIdentity: null,
  peerName: null,
  incomingRequest: null,
  notice: null,
  agentMissing: false,

  setRole: (role, peer = null) =>
    set({ role, peerIdentity: peer?.identity ?? null, peerName: peer?.name ?? null }),
  setIncomingRequest: (req) => set({ incomingRequest: req }),
  setNotice: (msg) => set({ notice: msg }),
  setAgentMissing: (v) => set({ agentMissing: v }),
  reset: () =>
    set({
      role: 'none',
      peerIdentity: null,
      peerName: null,
      incomingRequest: null,
      notice: null,
      agentMissing: false,
    }),
}));

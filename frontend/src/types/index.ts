// 全局类型定义

/** 统一 API 响应结构（与后端 pkg/response 对齐） */
export interface ApiResponse<T = unknown> {
  code: number;
  message: string;
  data?: T;
  error?: { type: string; detail?: string };
}

/** 分页数据 */
export interface PageData<T> {
  items: T[];
  total: number;
  page: number;
  page_size: number;
  pages: number;
}

/** 用户 */
export interface User {
  id: string;
  email: string;
  phone?: string;
  name: string;
  avatar_url?: string;
  role_id?: string;
  role_name?: string;
  status: 'active' | 'disabled';
}

/** 角色 */
export type RoleName = 'admin' | 'teacher' | 'student';

/** 登录返回 */
export interface LoginResult {
  tokens: TokenPair;
  user: {
    id: string;
    email: string;
    name: string;
    role: RoleName;
    avatar_url?: string;
  };
}

export interface TokenPair {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  token_type: string;
}

/** 会议状态 */
export type MeetingStatus = 'scheduled' | 'in_progress' | 'completed' | 'cancelled';

/** 会议类型 */
export type MeetingType = 'tutoring' | 'group_class' | 'webinar';

/** 会议 */
export interface Meeting {
  id: string;
  title: string;
  description?: string;
  organizer_id: string;
  organizer?: User;
  start_time: string;
  end_time?: string;
  status: MeetingStatus;
  meeting_type: MeetingType;
  room_name: string;
  settings: string;
  created_at: string;
  updated_at: string;
  participants?: MeetingParticipant[];
}

/** 参会人员 */
export interface MeetingParticipant {
  id: string;
  meeting_id: string;
  user_id: string;
  user?: User;
  participant_role: 'host' | 'speaker' | 'attendee';
  status: 'invited' | 'confirmed' | 'joined' | 'declined';
  joined_at?: string;
  left_at?: string;
}

/** 创建会议请求 */
export interface CreateMeetingRequest {
  title: string;
  description?: string;
  start_time: string;
  end_time?: string;
  meeting_type?: MeetingType;
  participant_ids?: string[];
  settings?: string;
}

/** LiveKit Token 响应 */
export interface LiveKitJoinInfo {
  livekit_url: string;
  token: string;
  room_name: string;
  meeting_id: string;
}

/** 聊天消息 */
export interface ChatMessage {
  id: string;
  meeting_id: string;
  user_id: string;
  user?: { id: string; name: string };
  content: string;
  created_at: string;
}

/** 会议材料 */
export interface Material {
  id: string;
  meeting_id: string;
  uploader_id: string;
  file_name: string;
  file_url: string;
  file_type: string;
  file_size: number;
  created_at: string;
}

/** 会议录制 */
export interface Recording {
  id: string;
  meeting_id: string;
  file_url: string;
  file_size_bytes: number;
  duration_sec: number;
  status: string;
  created_at: string;
}

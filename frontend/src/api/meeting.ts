// Meeting API：会议 CRUD + LiveKit Token 下发
// 注：响应拦截器已将 AxiosResponse 解包为 ApiResponse，故此处直接断言为业务体类型
import { http } from './http';
import type {
  ApiResponse,
  PageData,
  Meeting,
  CreateMeetingRequest,
  LiveKitJoinInfo,
  Recording,
  Material,
} from '@/types';

/** 创建会议 */
export function createMeeting(data: CreateMeetingRequest) {
  return http.post('/meetings', data) as unknown as Promise<ApiResponse<Meeting>>;
}

/** 获取我的会议列表（带分页 + 状态过滤） */
export function listMeetings(params?: { page?: number; page_size?: number; status?: string }) {
  return http.get('/meetings', { params }) as unknown as Promise<ApiResponse<PageData<Meeting>>>;
}

/** 获取会议详情 */
export function getMeeting(id: string) {
  return http.get(`/meetings/${id}`) as unknown as Promise<ApiResponse<Meeting>>;
}

/** 取消会议 */
export function cancelMeeting(id: string) {
  return http.delete(`/meetings/${id}`) as unknown as Promise<ApiResponse>;
}

/** 彻底删除已结束会议（同时删除录制视频与会议材料） */
export function purgeMeeting(id: string) {
  return http.delete(`/meetings/${id}/permanent`) as unknown as Promise<
    ApiResponse<{ deleted_recordings: number; deleted_materials: number }>
  >;
}

/** 标记加入会议 */
export function joinMeeting(id: string) {
  return http.post(`/meetings/${id}/join`) as unknown as Promise<ApiResponse<{ status: string }>>;
}

/** 获取 LiveKit 入会 Token */
export function getLiveKitJoinInfo(id: string) {
  return http.get(`/meetings/${id}/livekit-token`) as unknown as Promise<
    ApiResponse<LiveKitJoinInfo>
  >;
}

/** 组织者邀请参会者 */
export function inviteParticipants(meetingID: string, participantIDs: string[]) {
  return http.post(`/meetings/${meetingID}/invite`, { participant_ids: participantIDs }) as unknown as Promise<
    ApiResponse<{ added: number }>
  >;
}

/** 获取可邀请的用户列表（所有登录用户可查，支持 q 搜索） */
export function suggestUsers(q = '') {
  return http.get('/users/suggest', { params: { q } }) as unknown as Promise<
    ApiResponse<Array<{ id: string; name: string; email: string; role_name?: string }>>
  >;
}

/** 获取会议录制列表 */
export function listRecordings(meetingID: string) {
  return http.get(`/meetings/${meetingID}/recordings`) as unknown as Promise<ApiResponse<Recording[]>>;
}

/** 上传浏览器录制的视频文件并生成录制记录 */
export function uploadRecording(meetingID: string, blob: Blob, durationSec: number, fileName = 'recording.webm') {
  const form = new FormData();
  form.append('file', blob, fileName);
  form.append('duration_sec', String(Math.max(0, Math.round(durationSec))));
  return http.post(`/meetings/${meetingID}/recordings/upload`, form, {
    timeout: 300000, // 录制文件较大，放宽超时
  }) as unknown as Promise<ApiResponse<Recording>>;
}

/** 获取会议材料列表 */
export function listMaterials(meetingID: string) {
  return http.get(`/meetings/${meetingID}/materials`) as unknown as Promise<ApiResponse<Material[]>>;
}

/** 上传会议材料 */
export function uploadMaterial(meetingID: string, file: File) {
  const form = new FormData();
  form.append('file', file);
  return http.post(`/meetings/${meetingID}/materials`, form, {
    timeout: 300000,
  }) as unknown as Promise<ApiResponse<Material>>;
}

/** 删除会议材料 */
export function deleteMaterial(materialID: string) {
  return http.delete(`/materials/${materialID}`) as unknown as Promise<ApiResponse>;
}

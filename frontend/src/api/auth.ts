// Auth API：注册/登录/刷新
// 注：响应拦截器已将 AxiosResponse 解包为 ApiResponse，故此处直接断言为业务体类型
import { http } from './http';
import type { LoginResult, ApiResponse, User } from '@/types';

/** 用户注册 */
export function register(data: { email: string; password: string; name: string; role?: string }) {
  return http.post('/auth/register', data) as unknown as Promise<ApiResponse<User>>;
}

/** 用户登录 — 返回 Token 对 + 用户信息 */
export function login(data: { email: string; password: string }) {
  return http.post('/auth/login', data) as unknown as Promise<ApiResponse<LoginResult>>;
}

/** 刷新 Access Token */
export function refresh(refreshToken: string) {
  return http.post('/auth/refresh', {
    refresh_token: refreshToken,
  }) as unknown as Promise<ApiResponse<{ access_token: string }>>;
}

/** 获取当前用户信息 */
export function me() {
  return http.get('/auth/me') as unknown as Promise<
    ApiResponse<{ id: string; email: string; name: string; role: string }>
  >;
}

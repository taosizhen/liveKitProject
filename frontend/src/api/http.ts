// HTTP 客户端：封装 Axios，自动处理 JWT 鉴权
import axios, { AxiosError, AxiosResponse, InternalAxiosRequestConfig } from 'axios';
import type { ApiResponse } from '@/types';

// Token 存储 Key
const TOKEN_KEY = 'access_token';
const REFRESH_KEY = 'refresh_token';

/**
 * 动态构建 backend 基础 URL
 * 开发态（Vite dev）直连同主机的 8090 端口，协议跟随页面（HTTPS 页面必须用 HTTPS，避免混合内容被拦截）
 * 生产态走同源相对路径，由反向代理转发
 */
function buildBaseURL(): string {
  if (import.meta.env.DEV) {
    const proto = window.location.protocol === 'https:' ? 'https' : 'http';
    return `${proto}://${window.location.hostname}:8090/api/v1`;
  }
  return '/api/v1';
}

/** 根据当前页面协议构建 WebSocket 前缀（开发态直连 backend 8090） */
function buildWSPrefix(): string {
  if (import.meta.env.DEV) {
    const proto = window.location.protocol === 'https:' ? 'wss' : 'ws';
    return `${proto}://${window.location.hostname}:8090`;
  }
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  return `${proto}://${location.host}`;
}

/** 拼接后端 API 完整 URL（用于 fetch 调用绕过 Vite proxy） */
export function resolveAPI(path: string): string {
  const base = buildBaseURL();
  // path 已经包含 /api/v1 开头的话做替换，否则直接拼接
  if (path.startsWith('/api/v1')) {
    return base + path.slice('/api/v1'.length);
  }
  return base + path;
}

/** 拼接后端 WebSocket 完整 URL */
export function resolveWS(path: string): string {
  return buildWSPrefix() + path;
}

/** 创建 Axios 实例，开发环境直连 backend，生产环境走同源 */
export const http = axios.create({
  baseURL: buildBaseURL(),
  timeout: 15000,
});

/** 请求拦截器：自动注入 Authorization Header */
http.interceptors.request.use(
  (config: InternalAxiosRequestConfig) => {
    const token = localStorage.getItem(TOKEN_KEY);
    if (token && config.headers) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (err) => Promise.reject(err),
);

/** 响应拦截器：统一错误处理（成功时直接返回响应体 ApiResponse） */
http.interceptors.response.use(
  (resp) => {
    const data = resp.data as ApiResponse;
    // 业务层面失败（code !== 0）
    if (data.code !== 0) {
      return Promise.reject(new Error(data.message || '请求失败'));
    }
    // 解包 AxiosResponse → 直接返回 ApiResponse 业务体
    return data as unknown as AxiosResponse;
  },
  (err: AxiosError<ApiResponse>) => {
    const status = err.response?.status;
    const body = err.response?.data;

    // 401 → 清除 Token 并跳转登录
    if (status === 401) {
      localStorage.removeItem(TOKEN_KEY);
      localStorage.removeItem(REFRESH_KEY);
      const current = encodeURIComponent(window.location.pathname);
      window.location.href = `/login?redirect=${current}`;
    }

    const msg = body?.message || err.message || '网络异常';
    return Promise.reject(new Error(msg));
  },
);

/** 存取 Token 工具函数 */
export const tokenStorage = {
  get access() {
    return localStorage.getItem(TOKEN_KEY) ?? '';
  },
  set access(val: string) {
    localStorage.setItem(TOKEN_KEY, val);
  },
  get refresh() {
    return localStorage.getItem(REFRESH_KEY) ?? '';
  },
  set refresh(val: string) {
    localStorage.setItem(REFRESH_KEY, val);
  },
  clear() {
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(REFRESH_KEY);
  },
};

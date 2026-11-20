// Auth Store：管理登录态 + 用户信息
import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import * as authApi from '@/api/auth';
import { tokenStorage } from '@/api/http';
import type { RoleName } from '@/types';

interface AuthState {
  user: { id: string; email: string; name: string; role: RoleName } | null;
  loading: boolean;
  error: string | null;

  login: (email: string, password: string) => Promise<void>;
  register: (data: { email: string; password: string; name: string; role?: string }) => Promise<void>;
  logout: () => void;
  clearError: () => void;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      user: null,
      loading: false,
      error: null,

      /** 登录 */
      login: async (email, password) => {
        set({ loading: true, error: null });
        try {
          const resp = await authApi.login({ email, password });
          const { tokens, user } = resp.data!;
          tokenStorage.access = tokens.access_token;
          tokenStorage.refresh = tokens.refresh_token;
          set({ user, loading: false });
        } catch (e) {
          set({ error: (e as Error).message, loading: false });
          throw e;
        }
      },

      /** 注册（同时自动登录） */
      register: async (data) => {
        set({ loading: true, error: null });
        try {
          await authApi.register(data);
          // 注册成功后自动登录
          const resp = await authApi.login({ email: data.email, password: data.password });
          const { tokens, user } = resp.data!;
          tokenStorage.access = tokens.access_token;
          tokenStorage.refresh = tokens.refresh_token;
          set({ user, loading: false });
        } catch (e) {
          set({ error: (e as Error).message, loading: false });
          throw e;
        }
      },

      /** 登出：清除 Token + 用户态 */
      logout: () => {
        tokenStorage.clear();
        set({ user: null, error: null });
      },

      clearError: () => set({ error: null }),
    }),
    {
      name: 'auth-store',
      partialize: (state) => ({ user: state.user }), // 只持久化 user，不持久化 error/loading
    },
  ),
);

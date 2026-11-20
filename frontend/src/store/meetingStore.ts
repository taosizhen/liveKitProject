// Meeting Store：管理会议列表
import { create } from 'zustand';
import * as meetingApi from '@/api/meeting';
import type { Meeting, CreateMeetingRequest, PageData, MeetingStatus } from '@/types';

interface MeetingState {
  list: Meeting[];
  total: number;
  loading: boolean;
  error: string | null;

  fetchList: (params?: { page?: number; page_size?: number; status?: MeetingStatus }) => Promise<PageData<Meeting>>;
  create: (data: CreateMeetingRequest) => Promise<Meeting>;
  cancel: (id: string) => Promise<void>;
  clearError: () => void;
}

export const useMeetingStore = create<MeetingState>((set) => ({
  list: [],
  total: 0,
  loading: false,
  error: null,

  fetchList: async (params) => {
    set({ loading: true });
    try {
      const resp = await meetingApi.listMeetings(params);
      const page = resp.data!;
      set({ list: page.items, total: page.total, loading: false });
      return page;
    } catch (e) {
      set({ error: (e as Error).message, loading: false });
      throw e;
    }
  },

  create: async (data) => {
    try {
      const resp = await meetingApi.createMeeting(data);
      return resp.data!;
    } catch (e) {
      set({ error: (e as Error).message });
      throw e;
    }
  },

  cancel: async (id) => {
    try {
      await meetingApi.cancelMeeting(id);
    } catch (e) {
      set({ error: (e as Error).message });
      throw e;
    }
  },

  clearError: () => set({ error: null }),
}));

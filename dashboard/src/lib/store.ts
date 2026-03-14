import { create } from 'zustand';
import type { Page } from './types';

function getInitialTheme(): 'light' | 'dark' {
  const saved = localStorage.getItem('noongil-theme');
  if (saved === 'dark' || saved === 'light') return saved;
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function getInitialLocale(): 'en' | 'mn' {
  const saved = localStorage.getItem('noongil-lang');
  if (saved === 'en' || saved === 'mn') return saved;
  return 'en';
}

function getInitialPage(): Page {
  const hash = window.location.hash.replace('#/', '').replace('#', '');
  if (['checkins', 'causal', 'care-plan', 'messages'].includes(hash)) return hash as Page;
  return 'checkins';
}

function defaultDateRange() {
  const end = new Date();
  const start = new Date();
  start.setDate(start.getDate() - 30);
  return {
    start: start.toISOString().split('T')[0],
    end: end.toISOString().split('T')[0],
  };
}

interface AppState {
  theme: 'light' | 'dark';
  locale: 'en' | 'mn';
  page: Page;
  selectedMemberId: string | null;
  dateRange: { start: string; end: string };
  sidebarOpen: boolean;

  setTheme: (theme: 'light' | 'dark') => void;
  toggleTheme: () => void;
  setLocale: (locale: 'en' | 'mn') => void;
  setPage: (page: Page) => void;
  setSelectedMemberId: (id: string | null) => void;
  setDateRange: (range: { start: string; end: string }) => void;
  setSidebarOpen: (open: boolean) => void;
}

export const useStore = create<AppState>((set) => ({
  theme: getInitialTheme(),
  locale: getInitialLocale(),
  page: getInitialPage(),
  selectedMemberId: null,
  dateRange: defaultDateRange(),
  sidebarOpen: false,

  setTheme: (theme) => {
    localStorage.setItem('noongil-theme', theme);
    document.documentElement.classList.toggle('dark', theme === 'dark');
    set({ theme });
  },
  toggleTheme: () => {
    set((state) => {
      const next = state.theme === 'light' ? 'dark' : 'light';
      localStorage.setItem('noongil-theme', next);
      document.documentElement.classList.toggle('dark', next === 'dark');
      return { theme: next };
    });
  },
  setLocale: (locale) => {
    localStorage.setItem('noongil-lang', locale);
    set({ locale });
  },
  setPage: (page) => {
    window.location.hash = `#/${page}`;
    set({ page });
  },
  setSelectedMemberId: (id) => set({ selectedMemberId: id }),
  setDateRange: (dateRange) => set({ dateRange }),
  setSidebarOpen: (sidebarOpen) => set({ sidebarOpen }),
}));

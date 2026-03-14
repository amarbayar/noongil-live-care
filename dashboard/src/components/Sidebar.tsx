import { useStore } from '@/lib/store';
import { useT } from '@/lib/i18n';
import { useMe } from '@/lib/hooks';
import { signOut } from '@/lib/firebase';
import { cn } from '@/lib/utils';
import { Select } from '@/components/ui/select';
import {
  ClipboardCheck,
  BrainCircuit,
  HeartPulse,
  MessageSquare,
  LogOut,
  X,
} from 'lucide-react';
import type { Page } from '@/lib/types';

const navItems: { page: Page; icon: typeof ClipboardCheck; labelKey: string }[] = [
  { page: 'checkins', icon: ClipboardCheck, labelKey: 'nav_checkins' },
  { page: 'causal', icon: BrainCircuit, labelKey: 'nav_causal' },
  { page: 'care-plan', icon: HeartPulse, labelKey: 'nav_care_plan' },
  { page: 'messages', icon: MessageSquare, labelKey: 'nav_messages' },
];

export function Sidebar() {
  const t = useT();
  const page = useStore((s) => s.page);
  const setPage = useStore((s) => s.setPage);
  const sidebarOpen = useStore((s) => s.sidebarOpen);
  const setSidebarOpen = useStore((s) => s.setSidebarOpen);
  const selectedMemberId = useStore((s) => s.selectedMemberId);
  const setSelectedMemberId = useStore((s) => s.setSelectedMemberId);
  const { data: me } = useMe();

  return (
    <>
      {/* Mobile overlay */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 z-40 bg-black/50 lg:hidden"
          onClick={() => setSidebarOpen(false)}
        />
      )}
      <aside
        className={cn(
          'fixed top-0 left-0 z-50 flex h-full w-64 flex-col bg-sidebar text-sidebar-foreground transition-transform duration-300 lg:relative lg:translate-x-0',
          sidebarOpen ? 'translate-x-0' : '-translate-x-full'
        )}
      >
        {/* Logo area */}
        <div className="flex items-center justify-between px-5 py-5">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-blue-200 via-violet-500 to-teal-600">
              <span className="text-sm font-bold text-white">N</span>
            </div>
            <div>
              <div className="text-sm font-semibold">{t('app_title')}</div>
              <div className="text-xs text-sidebar-foreground/60">{t('app_subtitle')}</div>
            </div>
          </div>
          <button
            className="rounded-lg p-1 hover:bg-sidebar-accent lg:hidden"
            onClick={() => setSidebarOpen(false)}
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Member picker */}
        {me && me.members.length > 0 && (
          <div className="px-4 pb-4">
            <Select
              value={selectedMemberId ?? ''}
              onChange={(e) => setSelectedMemberId(e.target.value || null)}
              className="bg-sidebar-accent border-sidebar-border text-sidebar-foreground text-xs"
            >
              <option value="">{t('member_loading')}</option>
              {me.members.map((m) => (
                <option key={m.memberId} value={m.memberId}>
                  {m.memberName || m.memberId}
                </option>
              ))}
            </Select>
          </div>
        )}

        {/* Navigation */}
        <nav className="flex-1 space-y-1 px-3">
          {navItems.map(({ page: p, icon: Icon, labelKey }) => (
            <button
              key={p}
              onClick={() => {
                setPage(p);
                setSidebarOpen(false);
              }}
              className={cn(
                'flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-all duration-200',
                page === p
                  ? 'bg-primary/15 text-primary dark:bg-primary/20 dark:text-primary ring-1 ring-primary/25 shadow-sm'
                  : 'text-sidebar-foreground/60 hover:bg-sidebar-accent hover:text-sidebar-foreground hover:translate-x-0.5'
              )}
            >
              <Icon className={cn('h-4 w-4', page === p && 'text-primary')} />
              {t(labelKey)}
            </button>
          ))}
        </nav>

        {/* Sign out */}
        <div className="border-t border-sidebar-border p-4">
          <button
            onClick={() => signOut()}
            className="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium text-sidebar-foreground/70 hover:bg-sidebar-accent/50 hover:text-sidebar-foreground transition-colors"
          >
            <LogOut className="h-4 w-4" />
            {t('sign_out')}
          </button>
        </div>
      </aside>
    </>
  );
}

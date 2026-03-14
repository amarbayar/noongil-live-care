import { useEffect } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { AuthProvider, useAuthContext } from '@/features/auth/AuthProvider';
import { SignInPage } from '@/features/auth/SignInPage';
import { AppShell } from '@/components/AppShell';
import { CheckInsPage } from '@/features/checkins/CheckInsPage';
import { CausalEnginePage } from '@/features/causal/CausalEnginePage';
import { CarePlanPage } from '@/features/careplan/CarePlanPage';
import { MessagesPage } from '@/features/messages/MessagesPage';
import { useStore } from '@/lib/store';
import { useMe } from '@/lib/hooks';
import { Skeleton } from '@/components/ui/skeleton';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000,
      retry: 1,
    },
  },
});

function PageRouter() {
  const page = useStore((s) => s.page);

  switch (page) {
    case 'checkins':
      return <CheckInsPage />;
    case 'causal':
      return <CausalEnginePage />;
    case 'care-plan':
      return <CarePlanPage />;
    case 'messages':
      return <MessagesPage />;
    default:
      return <CheckInsPage />;
  }
}

function MemberAutoSelect({ children }: { children: React.ReactNode }) {
  const { data: me, isLoading } = useMe();
  const selectedMemberId = useStore((s) => s.selectedMemberId);
  const setSelectedMemberId = useStore((s) => s.setSelectedMemberId);

  useEffect(() => {
    if (!selectedMemberId && me?.members?.length) {
      setSelectedMemberId(me.members[0].memberId);
    }
  }, [me, selectedMemberId, setSelectedMemberId]);

  // Show loading skeleton until we know whether there are members
  if (isLoading) {
    return (
      <AppShell>
        <div className="space-y-6">
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {[...Array(4)].map((_, i) => (
              <Skeleton key={i} className="h-28 w-full rounded-2xl" />
            ))}
          </div>
          <Skeleton className="h-72 w-full rounded-2xl" />
        </div>
      </AppShell>
    );
  }

  return <>{children}</>;
}

function AuthGate() {
  const { user, loading } = useAuthContext();

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <div className="space-y-4 text-center">
          <Skeleton className="mx-auto h-16 w-16 rounded-2xl" />
          <Skeleton className="mx-auto h-4 w-40" />
          <Skeleton className="mx-auto h-3 w-56" />
        </div>
      </div>
    );
  }

  if (!user) {
    return <SignInPage />;
  }

  return (
    <MemberAutoSelect>
      <AppShell>
        <PageRouter />
      </AppShell>
    </MemberAutoSelect>
  );
}

function HashRouter() {
  const setPage = useStore((s) => s.setPage);

  useEffect(() => {
    const handleHash = () => {
      const hash = window.location.hash.replace('#/', '').replace('#', '');
      if (['checkins', 'causal', 'care-plan', 'messages'].includes(hash)) {
        setPage(hash as 'checkins' | 'causal' | 'care-plan' | 'messages');
      }
    };

    window.addEventListener('hashchange', handleHash);
    return () => window.removeEventListener('hashchange', handleHash);
  }, [setPage]);

  return null;
}

export default function App() {
  // Initialize theme on mount
  useEffect(() => {
    const theme = useStore.getState().theme;
    document.documentElement.classList.toggle('dark', theme === 'dark');
  }, []);

  return (
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <HashRouter />
        <AuthGate />
      </AuthProvider>
    </QueryClientProvider>
  );
}

import { useState, useEffect } from 'react';
import { onAuthChange, signInWithGoogle, signOut } from '@/lib/firebase';
import type { User } from 'firebase/auth';

export function useAuth() {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsubscribe = onAuthChange((u) => {
      setUser(u);
      setLoading(false);
    });
    return unsubscribe;
  }, []);

  return {
    user,
    loading,
    signIn: signInWithGoogle,
    signOut,
  };
}

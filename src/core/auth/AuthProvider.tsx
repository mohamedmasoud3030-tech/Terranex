import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import type { Session, User } from '@supabase/supabase-js';
import { supabase } from '../storage/supabaseClient';
import { clearAllStoreCaches, rehydrateAllStores } from '../storage/supabaseStore';

interface AuthContextValue {
  session: Session | null;
  user: User | null;
  loading: boolean;
  signInWithPassword: (email: string, password: string) => Promise<{ error: string | null }>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    let transition = 0;

    async function syncIdentity(nextSession: Session | null) {
      const currentTransition = ++transition;
      setLoading(true);

      if (nextSession) {
        // Stores are created before AuthProvider mounts, so their first anonymous
        // hydration is correctly denied by RLS. Reload them with the authenticated
        // identity before exposing the workspace to avoid a stale empty cache.
        await rehydrateAllStores();
      } else {
        // Never leave the previous identity's in-memory rows visible after sign-out
        // or while the login screen is shown.
        clearAllStoreCaches();
      }

      if (!active || currentTransition !== transition) return;
      setSession(nextSession);
      setLoading(false);
    }

    void supabase.auth.getSession().then(({ data }) => {
      void syncIdentity(data.session);
    });
    const { data: subscription } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      void syncIdentity(nextSession);
    });

    return () => {
      active = false;
      subscription.subscription.unsubscribe();
    };
  }, []);

  async function signInWithPassword(email: string, password: string) {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    return { error: error ? mapAuthError(error.message) : null };
  }

  async function signOut() {
    await supabase.auth.signOut();
  }

  return (
    <AuthContext.Provider value={{ session, user: session?.user ?? null, loading, signInWithPassword, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}

function mapAuthError(message: string): string {
  if (message.toLowerCase().includes('invalid login credentials')) {
    return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
  }
  if (message.toLowerCase().includes('email not confirmed')) {
    return 'لم يتم تأكيد البريد الإلكتروني بعد.';
  }
  return 'تعذر تسجيل الدخول. حاول مرة أخرى.';
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth يجب أن يُستخدم داخل AuthProvider.');
  return ctx;
}

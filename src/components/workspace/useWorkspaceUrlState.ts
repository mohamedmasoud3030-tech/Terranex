import { useCallback, useEffect, useState } from 'react';
export interface WorkspaceUrlStateOptions { parameter?: string; replace?: boolean }
function read(parameter: string, allowed: readonly string[], fallback: string) {
  if (typeof window === 'undefined') return fallback;
  const value = new URL(window.location.href).searchParams.get(parameter);
  return value && allowed.includes(value) ? value : fallback;
}
/** Shareable workspace selection without a route per workspace. */
export function useWorkspaceUrlState(allowed: readonly string[], fallback: string, { parameter = 'workspace', replace = true }: WorkspaceUrlStateOptions = {}) {
  const [value, setValue] = useState(() => read(parameter, allowed, fallback));
  useEffect(() => { const sync = () => setValue(read(parameter, allowed, fallback)); window.addEventListener('popstate', sync); return () => window.removeEventListener('popstate', sync); }, [allowed, fallback, parameter]);
  const select = useCallback((next: string) => {
    if (!allowed.includes(next)) return;
    const url = new URL(window.location.href);
    url.searchParams.set(parameter, next);
    window.history[replace ? 'replaceState' : 'pushState'](
      window.history.state,
      '',
      url,
    );
    setValue(next);
  }, [allowed, parameter, replace]);
  return [value, select] as const;
}

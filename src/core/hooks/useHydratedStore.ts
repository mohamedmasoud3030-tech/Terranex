import { useCallback, useEffect, useRef, useState } from 'react';

export type HydrationStatus = 'loading' | 'ready' | 'error';

/** Hydration side of a Supabase-backed store (`xxxHydration`). */
export interface HydrationHandle {
  ready: Promise<void>;
  rehydrate(): Promise<void>;
  getLoadError(): Error | null;
}

/** Read side of a feature store facade (`xxxStore`). */
export interface ReadableStore<T> {
  getAll(): T[];
  subscribe(listener: (rows: T[]) => void): () => void;
}

/** A store facade paired with the hydration handle of its backing store. */
export interface HydratedSource {
  store: { subscribe(listener: () => void): () => void };
  hydration: HydrationHandle;
}

function firstLoadError(sources: readonly HydratedSource[]): Error | null {
  return sources.map(({ hydration }) => hydration.getLoadError()).find(Boolean) ?? null;
}

/**
 * Subscribes to one hydrated collection and exposes its rows with the
 * hydration status, the hydration error and a retry that re-reads the table.
 *
 * `select` narrows the rows (e.g. by project). It is read from a ref so an
 * inline arrow does not resubscribe on every render; pass the values it closes
 * over as `selectDeps` instead.
 */
export function useHydratedCollection<T>(
  store: ReadableStore<T>,
  hydration: HydrationHandle,
  select?: (rows: T[]) => T[],
  selectDeps: readonly unknown[] = [],
) {
  const [items, setItems] = useState<T[]>([]);
  const [status, setStatus] = useState<HydrationStatus>('loading');
  const [error, setError] = useState<Error | null>(null);
  const selectRef = useRef(select);
  selectRef.current = select;

  const read = useCallback(() => {
    const rows = store.getAll();
    return selectRef.current ? selectRef.current(rows) : rows;
  }, [store]);

  useEffect(() => {
    let active = true;
    const unsubscribe = store.subscribe((rows) => {
      if (active) setItems(selectRef.current ? selectRef.current(rows) : rows);
    });
    void hydration.ready.then(() => {
      if (!active) return;
      const loadError = hydration.getLoadError();
      setItems(read());
      setError(loadError);
      setStatus(loadError ? 'error' : 'ready');
    });
    return () => {
      active = false;
      unsubscribe();
    };
  }, [store, hydration, read, ...selectDeps]);

  const retry = useCallback(async () => {
    setStatus('loading');
    setError(null);
    await hydration.rehydrate();
    const loadError = hydration.getLoadError();
    setItems(read());
    setError(loadError);
    setStatus(loadError ? 'error' : 'ready');
  }, [hydration, read]);

  return { items, status, error, retry };
}

/**
 * Subscribes to several hydrated stores at once and keeps a derived snapshot
 * in sync — the shape every hub data hook (finance, operations, portfolio,
 * governance, intelligence) needs.
 *
 * `snapshot` is only called once all sources have hydrated and then on every
 * store change, so it always reads consistent, hydrated rows.
 */
export function useHydratedSnapshot<T>(
  sources: readonly HydratedSource[],
  snapshot: () => T,
  empty: T,
) {
  const [data, setData] = useState<T>(empty);
  const [status, setStatus] = useState<HydrationStatus>('loading');
  const [error, setError] = useState<Error | null>(null);
  const snapshotRef = useRef(snapshot);
  snapshotRef.current = snapshot;
  const sourcesRef = useRef(sources);
  sourcesRef.current = sources;

  const settle = useCallback(() => {
    const loadError = firstLoadError(sourcesRef.current);
    setData(snapshotRef.current());
    setError(loadError);
    setStatus(loadError ? 'error' : 'ready');
  }, []);

  useEffect(() => {
    let active = true;
    const unsubscribers = sourcesRef.current.map(({ store }) =>
      store.subscribe(() => {
        if (active) setData(snapshotRef.current());
      }),
    );
    void Promise.all(sourcesRef.current.map(({ hydration }) => hydration.ready)).then(() => {
      if (active) settle();
    });
    return () => {
      active = false;
      unsubscribers.forEach((unsubscribe) => unsubscribe());
    };
  }, [settle]);

  const retry = useCallback(async () => {
    setStatus('loading');
    setError(null);
    await Promise.all(sourcesRef.current.map(({ hydration }) => hydration.rehydrate()));
    settle();
  }, [settle]);

  return { data, status, error, retry };
}

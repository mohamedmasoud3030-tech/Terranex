import type { ReactNode } from 'react';

/**
 * Bar list for counts or same-unit figures. The caller guarantees every row
 * shares one unit (and one currency, for money). A zero row is drawn empty,
 * never dropped.
 */
export type BarItem = {
  key: string;
  label: ReactNode;
  value: number;
  display?: ReactNode;
  tone?: 'cash' | 'rev' | 'exp';
};

export function BarList({ items, caption }: { items: readonly BarItem[]; caption?: ReactNode }) {
  if (items.length === 0) return null;
  const max = items.reduce((m, i) => (i.value > m ? i.value : m), 0);
  return (
    <div className="insight-bars">
      {caption ? <p className="muted insight-caption">{caption}</p> : null}
      <ul className="sector-bars">
        {items.map((item) => (
          <li key={item.key}>
            <div className="sector-bar-label">
              <span>{item.label}</span>
              <strong>{item.display ?? item.value}</strong>
            </div>
            <div className="sector-bar-track" aria-hidden="true">
              <span
                className={`sector-bar-fill ${item.tone ?? 'cash'}`}
                style={{ width: `${max > 0 && item.value > 0 ? Math.max(2, (item.value / max) * 100) : 0}%` }}
              />
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

/** Count rows grouped by a key, in the given label order, empty groups kept. */
export function countBy<T>(
  rows: readonly T[],
  keyOf: (row: T) => string,
  labels: Record<string, string>,
): BarItem[] {
  const counts = new Map<string, number>();
  for (const row of rows) counts.set(keyOf(row), (counts.get(keyOf(row)) ?? 0) + 1);
  const known = Object.keys(labels).filter((k) => counts.has(k));
  const extra = [...counts.keys()].filter((k) => !(k in labels));
  return [...known, ...extra].map((k) => ({
    key: k,
    label: labels[k] ?? k,
    value: counts.get(k) ?? 0,
  }));
}

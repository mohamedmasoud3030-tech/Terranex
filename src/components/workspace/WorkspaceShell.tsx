import type { ComponentType, ReactNode } from 'react';
import { cn } from '../../core/lib/cn';
import { EmptyState, ErrorState } from '../ui/States';
import { Skeleton } from '../ui/Skeleton';

export interface WorkspaceItem {
  id: string;
  label: string;
  description?: string;
  icon?: ComponentType<{ className?: string }>;
}

export interface WorkspaceShellProps {
  title: string;
  description?: string;
  actions?: ReactNode;
  summaries?: ReactNode;
  workspaces: readonly WorkspaceItem[];
  activeWorkspace: string;
  onWorkspaceChange: (id: string) => void;
  switcherLabel: string;
  loadingLabel: string;
  children: ReactNode;
  state?: 'ready' | 'loading' | 'empty' | 'error';
  emptyState?: {
    title: string;
    description: string;
    action?: { label: string; onClick: () => void };
  };
  errorState?: {
    title: string;
    description: string;
    onRetry?: () => void;
  };
}

export function WorkspaceShell({
  title,
  description,
  actions,
  summaries,
  workspaces,
  activeWorkspace,
  onWorkspaceChange,
  switcherLabel,
  loadingLabel,
  children,
  state = 'ready',
  emptyState,
  errorState,
}: WorkspaceShellProps) {
  return (
    <section aria-labelledby="workspace-title" className="space-y-5">
      <header className="surface-card rounded-3xl border p-5">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h1 id="workspace-title" className="text-2xl font-extrabold md:text-3xl">
              {title}
            </h1>
            {description && (
              <p className="mt-2 max-w-3xl text-sm leading-7 text-muted-foreground">
                {description}
              </p>
            )}
          </div>
          {actions && <div className="flex min-h-11 flex-wrap gap-2">{actions}</div>}
        </div>
        {summaries && <div className="mt-5">{summaries}</div>}
      </header>

      <div className="md:hidden">
        <label htmlFor="workspace-switcher" className="mb-2 block text-sm font-semibold">
          {switcherLabel}
        </label>
        <select
          id="workspace-switcher"
          value={activeWorkspace}
          onChange={(event) => onWorkspaceChange(event.target.value)}
          className="min-h-11 w-full rounded-xl border bg-card px-3"
        >
          {workspaces.map((workspace) => (
            <option key={workspace.id} value={workspace.id}>
              {workspace.label}
            </option>
          ))}
        </select>
      </div>

      <div className="grid gap-5 md:grid-cols-[15rem_minmax(0,1fr)]">
        <nav className="hidden md:block" aria-label={switcherLabel}>
          <ul className="space-y-2">
            {workspaces.map((workspace) => {
              const Icon = workspace.icon;
              const selected = workspace.id === activeWorkspace;
              return (
                <li key={workspace.id}>
                  <button
                    type="button"
                    onClick={() => onWorkspaceChange(workspace.id)}
                    aria-current={selected ? 'page' : undefined}
                    className={cn(
                      'min-h-11 w-full rounded-2xl border px-4 py-3 text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary',
                      selected
                        ? 'border-primary bg-primary text-primary-foreground'
                        : 'bg-card hover:bg-muted',
                    )}
                  >
                    <span className="flex items-center gap-2 font-semibold">
                      {Icon && <Icon className="h-5 w-5" />}
                      {workspace.label}
                    </span>
                    {workspace.description && (
                      <span className="mt-1 block text-xs opacity-80">
                        {workspace.description}
                      </span>
                    )}
                  </button>
                </li>
              );
            })}
          </ul>
        </nav>

        <div
          className="min-w-0"
          aria-live="polite"
          aria-busy={state === 'loading'}
        >
          {state === 'loading' && <WorkspaceLoadingState label={loadingLabel} />}
          {state === 'empty' && emptyState && <EmptyState {...emptyState} />}
          {state === 'error' && errorState && <ErrorState {...errorState} />}
          {state === 'ready' && children}
        </div>
      </div>
    </section>
  );
}

export function WorkspaceLoadingState({ label }: { label: string }) {
  return (
    <div
      role="status"
      aria-label={label}
      className="space-y-3 rounded-3xl border bg-card p-5"
    >
      <Skeleton className="h-8 w-1/3" />
      <Skeleton className="h-24" />
      <Skeleton className="h-24" />
    </div>
  );
}

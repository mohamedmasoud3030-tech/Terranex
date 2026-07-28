import { useRef, type ReactNode } from 'react';
import * as Dialog from '@radix-ui/react-dialog';
import { ExternalLink, X } from 'lucide-react';
import { Button } from './Button';

export interface EntityInspectorDrawerProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  description?: string;
  closeLabel: string;
  summary: ReactNode;
  relationships?: ReactNode;
  activity?: ReactNode;
  actions?: ReactNode;
  fullWorkspaceLink?: { label: string; href: string };
  relationshipsLabel: string;
  activityLabel: string;
}

export function EntityInspectorDrawer({
  open,
  onOpenChange,
  title,
  description,
  closeLabel,
  summary,
  relationships,
  activity,
  actions,
  fullWorkspaceLink,
  relationshipsLabel,
  activityLabel,
}: EntityInspectorDrawerProps) {
  const returnFocusRef = useRef<HTMLElement | null>(null);

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-40 bg-slate-950/55" />
        <Dialog.Content
          {...(description ? {} : { 'aria-describedby': undefined })}
          onOpenAutoFocus={() => {
            const active = document.activeElement;
            returnFocusRef.current = active instanceof HTMLElement ? active : null;
          }}
          onCloseAutoFocus={(event) => {
            if (returnFocusRef.current?.isConnected) {
              event.preventDefault();
              returnFocusRef.current.focus();
            }
          }}
          className="fixed inset-y-0 end-0 z-50 flex w-[min(40rem,calc(100vw-1rem))] flex-col border-s bg-card shadow-2xl focus:outline-none"
        >
          <header className="flex items-start justify-between border-b p-5">
            <div>
              <Dialog.Title className="text-xl font-extrabold">{title}</Dialog.Title>
              {description && (
                <Dialog.Description className="mt-1 text-sm text-muted-foreground">
                  {description}
                </Dialog.Description>
              )}
            </div>
            <Dialog.Close asChild>
              <Button variant="ghost" size="icon" aria-label={closeLabel}>
                <X className="h-5 w-5" />
              </Button>
            </Dialog.Close>
          </header>
          <div className="min-h-0 flex-1 space-y-6 overflow-y-auto p-5">
            <section>{summary}</section>
            {relationships && (
              <section>
                <h3 className="mb-3 font-bold">{relationshipsLabel}</h3>
                {relationships}
              </section>
            )}
            {activity && (
              <section>
                <h3 className="mb-3 font-bold">{activityLabel}</h3>
                {activity}
              </section>
            )}
          </div>
          {(actions || fullWorkspaceLink) && (
            <footer className="flex flex-wrap justify-end gap-3 border-t p-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
              {actions}
              {fullWorkspaceLink && (
                <a
                  href={fullWorkspaceLink.href}
                  className="inline-flex min-h-11 items-center gap-2 rounded-xl border px-4 text-sm font-semibold"
                >
                  {fullWorkspaceLink.label}
                  <ExternalLink className="h-4 w-4" />
                </a>
              )}
            </footer>
          )}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

import { type ReactNode } from 'react';
import * as Dialog from '@radix-ui/react-dialog';
import { X } from 'lucide-react';
import { Button } from './Button';
import { usePendingAction, useReturnFocus } from './dialogBehavior';

export type FormSurfaceMode = 'create' | 'edit' | 'read-only';

export interface AdaptiveFormSurfaceProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  description: string;
  children: ReactNode;
  mode?: FormSurfaceMode;
  pending?: boolean;
  submitLabel?: string;
  cancelLabel: string;
  closeLabel: string;
  onSubmit?: () => void | Promise<void>;
  formId?: string;
  error?: ReactNode;
}

export function AdaptiveFormSurface({
  open,
  onOpenChange,
  title,
  description,
  children,
  mode = 'create',
  pending = false,
  submitLabel,
  cancelLabel,
  closeLabel,
  onSubmit,
  formId,
  error,
}: AdaptiveFormSurfaceProps) {
  const returnFocus = useReturnFocus();
  const { isPending, run: submit } = usePendingAction(onSubmit, pending);

  return (
    <Dialog.Root
      open={open}
      onOpenChange={(next) => {
        if (!isPending) onOpenChange(next);
      }}
    >
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-40 bg-slate-950/60" />
        <Dialog.Content
          {...returnFocus}
          onEscapeKeyDown={(event) => {
            if (isPending) event.preventDefault();
          }}
          className="fixed inset-x-0 bottom-0 z-50 flex max-h-[calc(100dvh-1rem)] min-h-[70dvh] flex-col rounded-t-3xl border bg-card shadow-2xl focus:outline-none md:inset-auto md:start-1/2 md:top-1/2 md:min-h-0 md:w-[min(42rem,calc(100vw-2rem))] md:-translate-x-1/2 md:-translate-y-1/2 md:rounded-3xl rtl:md:translate-x-1/2"
        >
          <header className="flex items-start justify-between gap-4 border-b p-5">
            <div>
              <Dialog.Title className="text-xl font-extrabold">{title}</Dialog.Title>
              <Dialog.Description className="mt-1 text-sm text-muted-foreground">
                {description}
              </Dialog.Description>
            </div>
            <Dialog.Close asChild>
              <Button
                variant="ghost"
                size="icon"
                aria-label={closeLabel}
                disabled={isPending}
              >
                <X className="h-5 w-5" />
              </Button>
            </Dialog.Close>
          </header>
          <div className="min-h-0 flex-1 overflow-y-auto p-5">
            {error}
            {children}
          </div>
          <footer className="sticky bottom-0 flex min-h-[4.75rem] justify-end gap-3 border-t bg-card p-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
            <Dialog.Close asChild>
              <Button type="button" variant="secondary" disabled={isPending}>
                {cancelLabel}
              </Button>
            </Dialog.Close>
            {mode !== 'read-only' && (
              <Button
                type={formId ? 'submit' : 'button'}
                form={formId}
                onClick={formId ? undefined : () => void submit()}
                disabled={isPending}
                aria-busy={isPending}
              >
                {submitLabel}
              </Button>
            )}
          </footer>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

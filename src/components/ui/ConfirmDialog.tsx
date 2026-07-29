import { useRef, useState } from 'react';
import * as Dialog from '@radix-ui/react-dialog';
import { Button } from './Button';

export interface ConfirmDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  entityName: string;
  impact: string;
  confirmLabel: string;
  cancelLabel: string;
  onConfirm: () => void | Promise<void>;
  pending?: boolean;
  destructive?: boolean;
}

export function ConfirmDialog({
  open,
  onOpenChange,
  title,
  entityName,
  impact,
  confirmLabel,
  cancelLabel,
  onConfirm,
  pending = false,
  destructive = true,
}: ConfirmDialogProps) {
  const confirmLockRef = useRef(false);
  const returnFocusRef = useRef<HTMLElement | null>(null);
  const [confirming, setConfirming] = useState(false);
  const isPending = pending || confirming;

  const confirm = async () => {
    if (isPending || confirmLockRef.current) return;
    confirmLockRef.current = true;
    setConfirming(true);
    try {
      await onConfirm();
    } finally {
      confirmLockRef.current = false;
      setConfirming(false);
    }
  };

  return (
    <Dialog.Root
      open={open}
      onOpenChange={(next) => {
        if (!isPending) onOpenChange(next);
      }}
    >
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-50 bg-slate-950/60" />
        <Dialog.Content
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
          onEscapeKeyDown={(event) => {
            if (isPending) event.preventDefault();
          }}
          className="fixed start-1/2 top-1/2 z-50 w-[min(30rem,calc(100vw-2rem))] -translate-x-1/2 -translate-y-1/2 rounded-3xl border bg-card p-6 shadow-2xl focus:outline-none rtl:translate-x-1/2"
        >
          <Dialog.Title className="text-xl font-extrabold">{title}</Dialog.Title>
          <Dialog.Description className="mt-3 text-sm leading-7 text-muted-foreground">
            <strong className="text-foreground">{entityName}</strong>
            <br />
            {impact}
          </Dialog.Description>
          <div className="mt-6 flex justify-end gap-3">
            <Dialog.Close asChild>
              <Button variant="secondary" disabled={isPending}>
                {cancelLabel}
              </Button>
            </Dialog.Close>
            <Button
              variant={destructive ? 'danger' : 'primary'}
              onClick={() => void confirm()}
              disabled={isPending}
              aria-busy={isPending}
            >
              {confirmLabel}
            </Button>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

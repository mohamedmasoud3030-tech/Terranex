import { useRef, useState } from 'react';

/**
 * Radix `Dialog.Content` handlers that return focus to the element that opened
 * the dialog — required by every modal surface for keyboard accessibility.
 */
export function useReturnFocus() {
  const returnFocusRef = useRef<HTMLElement | null>(null);

  return {
    onOpenAutoFocus: () => {
      const active = document.activeElement;
      returnFocusRef.current = active instanceof HTMLElement ? active : null;
    },
    onCloseAutoFocus: (event: Event) => {
      if (returnFocusRef.current?.isConnected) {
        event.preventDefault();
        returnFocusRef.current.focus();
      }
    },
  };
}

/**
 * Runs an async action at most once at a time and reports whether it — or the
 * caller-supplied `pending` flag — is in flight. The lock is a ref so a double
 * click cannot fire the action twice before the state update lands.
 */
export function usePendingAction(action: (() => void | Promise<void>) | undefined, pending: boolean) {
  const lockRef = useRef(false);
  const [running, setRunning] = useState(false);
  const isPending = pending || running;

  const run = async () => {
    if (!action || isPending || lockRef.current) return;
    lockRef.current = true;
    setRunning(true);
    try {
      await action();
    } finally {
      lockRef.current = false;
      setRunning(false);
    }
  };

  return { isPending, run };
}

import { useEffect, type FormEventHandler, type ReactNode } from 'react';

type ModalOverlayProps = {
  children: ReactNode;
  closeLabel: string;
  contentClassName: string;
  onClose: () => void;
  onSubmit?: FormEventHandler<HTMLFormElement>;
  placement?: 'center' | 'start';
};

export function ModalOverlay({
  children,
  closeLabel,
  contentClassName,
  onClose,
  onSubmit,
  placement = 'center',
}: ModalOverlayProps) {
  useEffect(() => {
    function closeOnEscape(event: KeyboardEvent) {
      if (event.key === 'Escape') onClose();
    }

    document.addEventListener('keydown', closeOnEscape);
    return () => document.removeEventListener('keydown', closeOnEscape);
  }, [onClose]);

  const overlayClassName = placement === 'start'
    ? 'fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/50 p-4'
    : 'fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4';

  return (
    <div className={overlayClassName}>
      <button
        type="button"
        aria-label={closeLabel}
        className="absolute inset-0 cursor-default"
        onClick={onClose}
      />
      {onSubmit ? (
        <form
          role="dialog"
          aria-modal="true"
          className={`relative z-10 ${contentClassName}`}
          onSubmit={onSubmit}
        >
          {children}
        </form>
      ) : (
        <div role="dialog" aria-modal="true" className={`relative z-10 ${contentClassName}`}>
          {children}
        </div>
      )}
    </div>
  );
}

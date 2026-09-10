import type { ReactNode } from 'react';

/**
 * Form conventions (FORM_COMPONENT_STANDARD.md). Pure markup helpers; the
 * idempotency lifecycle and server validation stay in each form.
 */

/** Label + control + hint wiring. Pass the control as children. */
export function Field({
  label,
  optional = false,
  hint,
  error,
  children,
  className = '',
}: {
  label: ReactNode;
  optional?: boolean;
  hint?: ReactNode;
  error?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <label className={`field ${className}`.trim()}>
      <span className="field-label">
        {label}
        {optional ? <span className="muted"> (اختياري)</span> : null}
      </span>
      {children}
      {hint ? <small className="muted field-hint">{hint}</small> : null}
      {error ? <small className="error field-error">{error}</small> : null}
    </label>
  );
}

/** Action-level error. Always `role="alert"` so screen readers announce it. */
export function FormError({ error }: { error?: string | null }) {
  if (!error) return null;
  return (
    <p className="error" role="alert">
      {error}
    </p>
  );
}

/**
 * Aligns primary / secondary / cancel. Primary comes first in DOM (RTL: right
 * edge). On mobile actions stack and the primary spans the full width.
 */
export function FormActions({ children, note }: { children: ReactNode; note?: ReactNode }) {
  return (
    <div className="form-actions-wrap">
      <div className="form-actions">{children}</div>
      {note ? <p className="muted form-note">{note}</p> : null}
    </div>
  );
}

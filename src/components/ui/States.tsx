import { type ComponentType } from 'react';
import { FileText, AlertTriangle, RefreshCw } from 'lucide-react';
import { Button } from './Button';
import { cn } from '../../core/lib/cn';

interface EmptyStateProps {
  title: string;
  description: string;
  icon?: ComponentType<{ className?: string }>;
  action?: { label: string; onClick: () => void };
  className?: string;
}

export function EmptyState({
  title,
  description,
  icon: Icon = FileText,
  action,
  className,
}: EmptyStateProps) {
  return (
    <div className={cn('rounded-3xl border border-dashed border-border bg-card p-10 text-center', className)}>
      <Icon className="mx-auto h-10 w-10 text-muted-foreground" aria-hidden="true" />
      <h3 className="mt-4 text-lg font-bold">{title}</h3>
      <p className="mx-auto mt-2 max-w-sm text-sm leading-7 text-muted-foreground">{description}</p>
      {action && (
        <div className="mt-6">
          <Button variant="secondary" size="md" onClick={action.onClick}>
            {action.label}
          </Button>
        </div>
      )}
    </div>
  );
}

interface ErrorStateProps {
  title?: string;
  description?: string;
  onRetry?: () => void;
  className?: string;
}

export function ErrorState({
  title = 'خطأ في تحميل البيانات',
  description = 'تعذّر تحميل البيانات. يرجى المحاولة مجددًا.',
  onRetry,
  className,
}: ErrorStateProps) {
  return (
    <div
      className={cn('rounded-3xl border border-danger/30 bg-danger/5 p-6', className)}
      role="alert"
    >
      <div className="flex items-start gap-3 text-danger">
        <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0" aria-hidden="true" />
        <div className="flex-1">
          <p className="font-semibold">{title}</p>
          <p className="mt-1 text-sm leading-6 text-danger/80">{description}</p>
          {onRetry && (
            <button
              onClick={onRetry}
              className="mt-3 inline-flex items-center gap-2 text-sm font-semibold text-danger underline-offset-4 hover:underline"
            >
              <RefreshCw className="h-4 w-4" aria-hidden="true" />
              إعادة المحاولة
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

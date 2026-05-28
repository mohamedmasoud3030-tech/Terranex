import { type ReactNode } from 'react';
import { Button } from '../ui/Button';

interface PageHeaderProps {
  title: string;
  description?: string;
  action?: { label: string; onClick: () => void };
  children?: ReactNode;
}

export function PageHeader({ title, description, action, children }: PageHeaderProps) {
  return (
    <div className="mb-6 flex flex-col gap-4 rounded-3xl border border-border bg-card p-5 lg:flex-row lg:items-center lg:justify-between">
      <div className="flex-1">
        {description && (
          <p className="text-sm text-muted-foreground">{description}</p>
        )}
        <h2 className="mt-1 text-2xl font-bold md:text-3xl">{title}</h2>
      </div>
      <div className="flex items-center gap-3">
        {children}
        {action && (
          <Button onClick={action.onClick}>{action.label}</Button>
        )}
      </div>
    </div>
  );
}

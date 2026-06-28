import type { ReactNode } from 'react';
import type { LucideIcon } from 'lucide-react';
import { cn } from '../../core/lib/cn';
import { Card, CardContent } from './Card';

export type MetricTone = 'default' | 'positive' | 'negative' | 'warning' | 'primary';

const TONE_CLASS: Record<MetricTone, string> = {
  default: 'text-foreground',
  positive: 'text-success',
  negative: 'text-danger',
  warning: 'text-warning',
  primary: 'text-primary',
};

interface MetricCardProps {
  label: string;
  value: ReactNode;
  unit?: string;
  hint?: string;
  icon?: LucideIcon;
  tone?: MetricTone;
  className?: string;
  valueClassName?: string;
  align?: 'start' | 'center';
}

export function MetricCard({
  label,
  value,
  unit,
  hint,
  icon: Icon,
  tone = 'default',
  className,
  valueClassName,
  align = 'start',
}: MetricCardProps) {
  return (
    <Card className={className}>
      <CardContent className={cn('p-4', align === 'center' && 'text-center')}>
        <div className="mb-2 flex items-center justify-between gap-3">
          <span className="text-xs text-muted-foreground">{label}</span>
          {Icon && <Icon className={cn('h-4 w-4', TONE_CLASS[tone])} />}
        </div>
        <p className={cn('text-xl font-bold', TONE_CLASS[tone], valueClassName)}>{value}</p>
        {unit && <p className="text-xs text-muted-foreground">{unit}</p>}
        {hint && <p className="mt-0.5 text-xs text-muted-foreground">{hint}</p>}
      </CardContent>
    </Card>
  );
}

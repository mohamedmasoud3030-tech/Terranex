import type { ReactNode } from 'react';
import { cn } from '../../core/lib/cn';

export interface DetailRowItem {
  id: string;
  label: ReactNode;
  value: ReactNode;
  valueClassName?: string;
}

interface DetailRowsProps {
  items: DetailRowItem[];
  className?: string;
  rowClassName?: string;
}

export function DetailRows({ items, className, rowClassName }: DetailRowsProps) {
  return (
    <dl className={cn('space-y-2 text-sm', className)}>
      {items.map((item) => (
        <div key={item.id} className={cn('flex justify-between gap-3', rowClassName)}>
          <dt className="text-muted-foreground">{item.label}</dt>
          <dd className={cn('font-medium text-end', item.valueClassName)}>{item.value}</dd>
        </div>
      ))}
    </dl>
  );
}

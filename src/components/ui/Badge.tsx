import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '../../core/lib/cn';
import type { StatusTone } from '../../core/types/ui';

const badgeVariants = cva(
  'inline-flex items-center rounded-full border px-2.5 py-1 text-xs font-semibold',
  {
    variants: {
      tone: {
        neutral: 'border-border bg-muted text-muted-foreground',
        positive: 'border-success/30 bg-success/10 text-success',
        negative: 'border-danger/30 bg-danger/10 text-danger',
        warning: 'border-warning/30 bg-warning/10 text-warning',
        info: 'border-info/30 bg-info/10 text-info',
      },
    },
    defaultVariants: { tone: 'neutral' },
  },
);

export interface BadgeProps
  extends React.HTMLAttributes<HTMLSpanElement>,
    VariantProps<typeof badgeVariants> {
  tone?: StatusTone;
}

import React from 'react';

export function Badge({ className, tone = 'neutral', ...props }: BadgeProps) {
  return <span className={cn(badgeVariants({ tone }), className)} {...props} />;
}

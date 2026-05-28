import { useI18n } from '../../core/i18n';
import { formatMoney } from '../../core/lib/format';
import type { Currency } from '../../core/types';
import { cn } from '../../core/lib/cn';

interface MoneyValueProps {
  amount: number;
  currency: Currency;
  egpEquivalent?: number; // shown as tooltip or secondary label
  size?: 'sm' | 'md' | 'lg' | 'xl';
  showEquivalent?: boolean;
  className?: string;
}

const sizeClass = {
  sm: 'text-sm',
  md: 'text-base',
  lg: 'text-xl font-bold',
  xl: 'text-2xl font-bold',
};

export function MoneyValue({
  amount,
  currency,
  egpEquivalent,
  size = 'md',
  showEquivalent = false,
  className,
}: MoneyValueProps) {
  const { locale } = useI18n();

  return (
    <span className={cn('inline-flex flex-col', className)}>
      <span className={cn('tabular-nums', sizeClass[size])}>
        {formatMoney(amount, currency, locale)}
      </span>
      {showEquivalent && egpEquivalent !== undefined && currency !== 'EGP' && (
        <span className="text-xs text-muted-foreground tabular-nums">
          ≈ {formatMoney(egpEquivalent, 'EGP', locale)}
        </span>
      )}
    </span>
  );
}

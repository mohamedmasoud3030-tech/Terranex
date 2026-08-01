import { useEffect, useRef } from 'react';
import type { Currency } from '../../core/types/domain';
import { getLatestFxRate } from './ExchangeRateSection';

/**
 * Keeps a form's `fx_rate` field in step with the selected currency:
 *   EGP           → force 1 (always)
 *   foreign, new  → load the latest stored rate
 *   foreign, same → keep the current value, so manual edits survive re-renders
 *
 * `applyRate` must be stable (wrap it in `useCallback`) — it runs whenever the
 * currency changes.
 */
export function useAutoFxRate(currency: string, applyRate: (rate: number) => void) {
  const previousCurrencyRef = useRef(currency);

  useEffect(() => {
    const previousCurrency = previousCurrencyRef.current;
    previousCurrencyRef.current = currency;
    if (currency === 'EGP') {
      applyRate(1);
      return;
    }
    if (currency !== previousCurrency) {
      const stored = getLatestFxRate(currency as Currency);
      if (stored !== null) applyRate(stored);
    }
  }, [applyRate, currency]);
}

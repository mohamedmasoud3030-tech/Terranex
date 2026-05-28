import { useState } from 'react';
import { periodToDateRange } from '../lib/date';
import type { DateRange, PeriodFilter } from '../types';

export interface UsePeriodFilterReturn {
  period: PeriodFilter;
  dateRange: DateRange | null;
  customRange: DateRange | null;
  setPeriod: (p: PeriodFilter) => void;
  setCustomRange: (r: DateRange) => void;
}

export function usePeriodFilter(defaultPeriod: PeriodFilter = 'quarter'): UsePeriodFilterReturn {
  const [period, setPeriod] = useState<PeriodFilter>(defaultPeriod);
  const [customRange, setCustomRange] = useState<DateRange | null>(null);

  const dateRange: DateRange | null =
    period === 'custom' ? customRange : periodToDateRange(period);

  return { period, dateRange, customRange, setPeriod, setCustomRange };
}

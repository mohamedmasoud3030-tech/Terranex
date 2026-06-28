import { 
  ResponsiveContainer, 
  AreaChart, 
  Area, 
  XAxis, 
  YAxis, 
  CartesianGrid, 
  Tooltip, 
  Legend 
} from 'recharts';
import { useMemo } from 'react';
import type { Transaction } from '../../core/types/domain';
import { formatEgp } from '../../core/lib/profitability';

interface RevenueChartProps {
  transactions: Transaction[];
  height?: number;
}

export function RevenueChart({ transactions, height = 280 }: RevenueChartProps) {
  const data = useMemo(() => {
    // Group by month
    const map = new Map<string, { income: number; expense: number }>();
    transactions.forEach(tx => {
      const month = tx.transaction_date.slice(0, 7); // YYYY-MM
      const cur = map.get(month) ?? { income: 0, expense: 0 };
      if (tx.direction === 'income') cur.income += tx.amount_egp;
      else cur.expense += tx.amount_egp;
      map.set(month, cur);
    });
    return Array.from(map.entries())
      .sort(([a], [b]) => a.localeCompare(b))
      .slice(-12) // last 12 months
      .map(([month, v]) => ({
        month,
        monthLabel: new Date(month + '-01').toLocaleDateString('ar-EG', { month: 'short', year: '2-digit' }),
        income: v.income,
        expense: v.expense,
        profit: v.income - v.expense,
      }));
  }, [transactions]);

  if (data.length === 0) {
    return (
      <div style={{ height }} className="flex items-center justify-center text-sm text-muted-foreground border border-dashed border-border rounded-2xl">
        لا توجد بيانات كافية للرسم البياني — أضف معاملات أولاً
      </div>
    );
  }

  return (
    <div style={{ height }} dir="ltr">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
          <defs>
            <linearGradient id="incomeGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="#16a34a" stopOpacity={0.25}/>
              <stop offset="95%" stopColor="#16a34a" stopOpacity={0}/>
            </linearGradient>
            <linearGradient id="expenseGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="#dc2626" stopOpacity={0.25}/>
              <stop offset="95%" stopColor="#dc2626" stopOpacity={0}/>
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
          <XAxis 
            dataKey="monthLabel" 
            tick={{ fontSize: 11, fill: '#64748b' }}
            axisLine={false}
            tickLine={false}
          />
          <YAxis 
            tick={{ fontSize: 11, fill: '#64748b' }}
            axisLine={false}
            tickLine={false}
            tickFormatter={(v) => formatEgp(v, true)}
            width={50}
          />
          <Tooltip 
            formatter={(value: any, name: any) => [
              `${formatEgp(Number(value) || 0)} EGP`,
              name === 'income' ? 'إيرادات' : name === 'expense' ? 'مصروفات' : 'ربح'
            ]}
            labelFormatter={(l) => `الشهر: ${l}`}
            contentStyle={{ 
              backgroundColor: 'white', 
              border: '1px solid #e2e8f0',
              borderRadius: '12px',
              fontSize: '12px',
              direction: 'rtl',
              textAlign: 'right'
            }}
          />
          <Legend 
            formatter={(value) => 
              value === 'income' ? 'الإيرادات' : 
              value === 'expense' ? 'المصروفات' : value
            }
            wrapperStyle={{ fontSize: '12px', paddingTop: '10px' }}
          />
          <Area 
            type="monotone" 
            dataKey="income" 
            name="income"
            stroke="#16a34a" 
            strokeWidth={2}
            fill="url(#incomeGrad)" 
          />
          <Area 
            type="monotone" 
            dataKey="expense" 
            name="expense"
            stroke="#dc2626" 
            strokeWidth={2}
            fill="url(#expenseGrad)" 
          />
        </AreaChart>
      </ResponsiveContainer>
      {/* Numeric fallback — ADR charts rule: always show numbers */}
      <div className="mt-2 grid grid-cols-3 gap-2 text-[11px] text-muted-foreground text-center" dir="rtl">
        {data.slice(-3).map(d => (
          <div key={d.month}>
            {d.monthLabel}: <span className="text-success">{formatEgp(d.income, true)}</span> / <span className="text-danger">{formatEgp(d.expense, true)}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

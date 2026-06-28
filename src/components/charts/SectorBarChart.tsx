import { ResponsiveContainer, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Cell } from 'recharts';
import { formatEgp } from '../../core/lib/profitability';
import type { SectorId } from '../../core/types/domain';

interface SectorBarChartProps {
  data: Array<{ sector_id: SectorId; label_ar: string; profit_egp: number; income_egp: number; expense_egp: number }>;
  height?: number;
}

const SECTOR_COLORS: Record<SectorId, string> = {
  'real-estate': '#1e3a8a',
  'agriculture': '#4a7c23',
  'livestock': '#92400e',
};

export function SectorBarChart({ data, height = 220 }: SectorBarChartProps) {
  const chartData = data.map(d => ({
    ...d,
    color: d.profit_egp >= 0 ? SECTOR_COLORS[d.sector_id] : '#dc2626',
  }));

  if (chartData.length === 0 || chartData.every(d => d.profit_egp === 0 && d.income_egp === 0)) {
    return (
      <div style={{ height }} className="flex items-center justify-center text-sm text-muted-foreground border border-dashed border-border rounded-2xl">
        لا توجد بيانات قطاعية بعد
      </div>
    );
  }

  return (
    <div style={{ height }} dir="ltr">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={chartData} margin={{ top: 5, right: 10, left: 0, bottom: 5 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" vertical={false} />
          <XAxis 
            dataKey="label_ar" 
            tick={{ fontSize: 11, fill: '#64748b' }}
            axisLine={false}
            tickLine={false}
          />
          <YAxis 
            tickFormatter={(v) => formatEgp(v, true)}
            tick={{ fontSize: 11, fill: '#64748b' }}
            axisLine={false}
            tickLine={false}
            width={45}
          />
          <Tooltip 
            formatter={(value: any) => [`${formatEgp(Number(value) || 0)} EGP`, 'الربح']}
            contentStyle={{ 
              backgroundColor: 'white', 
              border: '1px solid #e2e8f0',
              borderRadius: '12px',
              fontSize: '12px',
              direction: 'rtl',
              textAlign: 'right'
            }}
            cursor={{ fill: 'rgba(0,0,0,0.03)' }}
          />
          <Bar dataKey="profit_egp" radius={[6, 6, 0, 0]}>
            {chartData.map((entry, index) => (
              <Cell key={`cell-${index}`} fill={entry.color} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
      {/* numeric fallback */}
      <div className="mt-2 flex justify-center gap-4 text-[11px] text-muted-foreground flex-wrap" dir="rtl">
        {chartData.map(d => (
          <span key={d.sector_id}>
            {d.label_ar}: <b className={d.profit_egp >= 0 ? 'text-success' : 'text-danger'}>{formatEgp(d.profit_egp, true)} EGP</b>
          </span>
        ))}
      </div>
    </div>
  );
}

export type Currency = 'OMR' | 'EGP' | 'SAR';

export type Kpi = {
  id: string;
  title: string;
  value: number;
  currency?: Currency;
  period: string;
  trendLabel: string;
  status: 'neutral' | 'positive' | 'negative' | 'warning';
  sourceLabel: string;
};

export type Sector = {
  id: string;
  title: string;
  description: string;
  metric: string;
  value: string;
  status: 'active' | 'review' | 'stable';
  href: string;
};

export type Obligation = {
  id: string;
  date: string;
  type: string;
  sector: string;
  counterparty: string;
  amount: number;
  currency: Currency;
  status: 'مستحق' | 'مدفوع' | 'قيد المراجعة';
  document: string;
};

export const dashboardKpis: Kpi[] = [
  {
    id: 'assets-total',
    title: 'إجمالي الأصول',
    value: 1250000,
    currency: 'OMR',
    period: 'الربع الحالي',
    trendLabel: 'قابل للتفصيل حسب القطاع',
    status: 'neutral',
    sourceLabel: 'سجل الأصول',
  },
  {
    id: 'expenses-total',
    title: 'إجمالي المصروفات',
    value: 186000,
    currency: 'OMR',
    period: 'آخر 90 يوم',
    trendLabel: 'تحتاج تصنيف نهائي',
    status: 'warning',
    sourceLabel: 'سجل المصروفات',
  },
  {
    id: 'revenue-total',
    title: 'إجمالي الإيرادات',
    value: 244000,
    currency: 'OMR',
    period: 'آخر 90 يوم',
    trendLabel: 'إيرادات تشغيلية ومبيعات',
    status: 'positive',
    sourceLabel: 'سجل الإيرادات',
  },
  {
    id: 'profit-net',
    title: 'صافي الربح / الخسارة',
    value: 58000,
    currency: 'OMR',
    period: 'آخر 90 يوم',
    trendLabel: 'قبل اعتماد القيود النهائية',
    status: 'positive',
    sourceLabel: 'ملخص الربحية',
  },
];

export const sectors: Sector[] = [
  {
    id: 'real-estate',
    title: 'الاستثمار العقاري',
    description: 'أراضي، أصول، شراء، تطوير، بيع، مستندات ملكية وربحية.',
    metric: 'أصول مسجلة',
    value: '12',
    status: 'active',
    href: '#real-estate',
  },
  {
    id: 'agriculture',
    title: 'الاستثمار الزراعي',
    description: 'مزارع، محاصيل، مواسم، إنتاج، مصروفات ومبيعات.',
    metric: 'مواسم نشطة',
    value: '5',
    status: 'review',
    href: '#agriculture',
  },
  {
    id: 'livestock',
    title: 'الاستثمار الحيواني',
    description: 'قطعان، أعلاف، علاج، تحصينات، ولادات، نفوق ومبيعات.',
    metric: 'قطعان متابعة',
    value: '8',
    status: 'stable',
    href: '#livestock',
  },
  {
    id: 'finance',
    title: 'المالية والالتزامات',
    description: 'إيرادات، مصروفات، ذمم مدينة، ذمم دائنة، وربط بالمستندات.',
    metric: 'بنود مراجعة',
    value: '17',
    status: 'review',
    href: '#finance',
  },
];

export const obligations: Obligation[] = [
  {
    id: 'obl-001',
    date: '2026-05-01',
    type: 'ذمة مدينة',
    sector: 'عقاري',
    counterparty: 'شريك تطوير',
    amount: 32000,
    currency: 'OMR',
    status: 'مستحق',
    document: 'عقد تطوير رقم 12',
  },
  {
    id: 'obl-002',
    date: '2026-05-09',
    type: 'ذمة دائنة',
    sector: 'زراعي',
    counterparty: 'مورد مدخلات',
    amount: 8400,
    currency: 'OMR',
    status: 'قيد المراجعة',
    document: 'فاتورة مدخلات موسم 2026',
  },
  {
    id: 'obl-003',
    date: '2026-05-14',
    type: 'ذمة دائنة',
    sector: 'حيواني',
    counterparty: 'عيادة بيطرية',
    amount: 2150,
    currency: 'OMR',
    status: 'مدفوع',
    document: 'إيصال علاج وتحصينات',
  },
];

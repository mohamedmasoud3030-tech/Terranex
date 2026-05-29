import type { AssetRowVM, KpiCardVM, ObligationRowVM, StatusTone, TransactionRowVM } from '../../core/types/ui';

export interface EquityPartnerVM {
  id: string;
  name_ar: string;
  equity_pct: number;
}

export interface DocumentVM {
  id: string;
  title_ar: string;
  type_ar: string;
  date?: string;
}

export interface RealEstateAssetDetail extends AssetRowVM {
  acquisition_date: string;
  valuation_date: string;
  notes: string;
  partners: EquityPartnerVM[];
  transactions: TransactionRowVM[];
  obligations: ObligationRowVM[];
  documents: DocumentVM[];
}

export const realEstateAssets: RealEstateAssetDetail[] = [
  {
    id: 'asset-re-001',
    sector_id: 'real-estate',
    project_name_ar: 'مشروع أرض كورنيش النيل',
    name_ar: 'أرض كورنيش النيل — 2,400 م²',
    type: 'land',
    status: 'under_development',
    location: 'كورنيش النيل، القاهرة',
    acquisition_date: '2021-03-15',
    valuation_date: '2025-12-01',
    acquisition_cost_egp: 8_500_000,
    development_cost_egp: 1_240_000,
    current_valuation_egp: 14_200_000,
    profit_loss_egp: 4_460_000,
    profit_loss_pct: 45.8,
    document_count: 3,
    notes: 'أصل تجاري عالي القيمة، قيد استكمال التراخيص والتطوير الرأسمالي.',
    partners: [
      { id: 'partner-001', name_ar: 'محمد أحمد الشريك', equity_pct: 60 },
      { id: 'partner-002', name_ar: 'صندوق الخليج للاستثمار', equity_pct: 40 },
    ],
    transactions: [
      {
        id: 'txn-re-001',
        date: '2021-03-15',
        direction: 'expense',
        category_ar: 'شراء أصل',
        category_en: 'Asset acquisition',
        counterparty_ar: 'مالك الأرض السابق',
        amount: 8_500_000,
        currency: 'EGP',
        amount_egp: 8_500_000,
        document_title: 'عقد شراء الأرض',
        notes: 'تكلفة الاستحواذ الأساسية.',
      },
      {
        id: 'txn-re-002',
        date: '2023-06-01',
        direction: 'expense',
        category_ar: 'تكلفة تطوير',
        category_en: 'Development CAPEX',
        counterparty_ar: 'شركة البناء الحديث',
        amount: 750_000,
        currency: 'EGP',
        amount_egp: 750_000,
        document_title: 'مستخلص تسوية الأرض',
      },
      {
        id: 'txn-re-003',
        date: '2024-02-10',
        direction: 'expense',
        category_ar: 'قانوني وإداري',
        category_en: 'Legal & admin',
        counterparty_ar: 'مصلحة التسجيل العقاري',
        amount: 490_000,
        currency: 'EGP',
        amount_egp: 490_000,
        document_title: 'رسوم التسجيل والرخص',
      },
    ],
    obligations: [
      {
        id: 'obl-re-001',
        date: '2026-06-30',
        direction: 'payable',
        sector_ar: 'عقاري',
        sector_en: 'Real Estate',
        counterparty_ar: 'شركة البناء الحديث',
        amount: 490_000,
        currency: 'EGP',
        amount_egp: 490_000,
        status: 'open',
        document_title: 'عقد التسوية',
        project_name_ar: 'مشروع أرض كورنيش النيل',
      },
    ],
    documents: [
      { id: 'doc-re-001', title_ar: 'عقد شراء الأرض', type_ar: 'عقد', date: '2021-03-15' },
      { id: 'doc-re-002', title_ar: 'محضر استلام الأصل', type_ar: 'مستند ملكية', date: '2021-03-20' },
      { id: 'doc-re-003', title_ar: 'تقييم خبير مستقل', type_ar: 'تقييم', date: '2025-12-01' },
    ],
  },
  {
    id: 'asset-re-002',
    sector_id: 'real-estate',
    project_name_ar: 'مشروع تطوير مبنى الإسكندرية',
    name_ar: 'مبنى سموحة — الإسكندرية',
    type: 'building',
    status: 'owned',
    location: 'سموحة، الإسكندرية',
    acquisition_date: '2022-07-10',
    valuation_date: '2025-10-15',
    acquisition_cost_egp: 5_200_000,
    development_cost_egp: 3_100_000,
    current_valuation_egp: 9_800_000,
    profit_loss_egp: 1_500_000,
    profit_loss_pct: 18.1,
    document_count: 5,
    notes: 'مبنى مملوك بعد تطوير رأسمالي كامل، مناسب للاحتفاظ أو البيع عند تحقق السعر المستهدف.',
    partners: [
      { id: 'partner-001', name_ar: 'محمد أحمد الشريك', equity_pct: 75 },
      { id: 'partner-002', name_ar: 'صندوق الخليج للاستثمار', equity_pct: 25 },
    ],
    transactions: [
      {
        id: 'txn-re-004',
        date: '2022-07-10',
        direction: 'expense',
        category_ar: 'شراء أصل',
        category_en: 'Asset acquisition',
        amount: 5_200_000,
        currency: 'EGP',
        amount_egp: 5_200_000,
        document_title: 'عقد شراء المبنى',
      },
      {
        id: 'txn-re-005',
        date: '2023-09-01',
        direction: 'expense',
        category_ar: 'تكلفة تطوير',
        category_en: 'Development CAPEX',
        counterparty_ar: 'شركة البناء الحديث',
        amount: 3_100_000,
        currency: 'EGP',
        amount_egp: 3_100_000,
        document_title: 'مستخلص التشطيب',
      },
    ],
    obligations: [
      {
        id: 'obl-re-002',
        date: '2026-08-01',
        direction: 'payable',
        sector_ar: 'عقاري',
        sector_en: 'Real Estate',
        counterparty_ar: 'شركة البناء الحديث',
        amount: 800_000,
        currency: 'EGP',
        amount_egp: 800_000,
        status: 'partial',
        document_title: 'عقد التشطيب',
        project_name_ar: 'مشروع تطوير مبنى الإسكندرية',
      },
    ],
    documents: [
      { id: 'doc-re-004', title_ar: 'عقد شراء المبنى', type_ar: 'عقد', date: '2022-07-10' },
      { id: 'doc-re-005', title_ar: 'مستخلص التشطيب النهائي', type_ar: 'فاتورة', date: '2023-09-01' },
      { id: 'doc-re-006', title_ar: 'تقييم سوقي محدث', type_ar: 'تقييم', date: '2025-10-15' },
    ],
  },
  {
    id: 'asset-re-003',
    sector_id: 'real-estate',
    project_name_ar: 'صفقة أرض العين السخنة',
    name_ar: 'أرض العين السخنة — مُباعة',
    type: 'land',
    status: 'sold',
    location: 'العين السخنة، السويس',
    acquisition_date: '2020-02-01',
    valuation_date: '2024-06-15',
    acquisition_cost_egp: 3_000_000,
    development_cost_egp: 0,
    current_valuation_egp: 6_500_000,
    sale_price_egp: 6_500_000,
    profit_loss_egp: 3_500_000,
    profit_loss_pct: 116.7,
    document_count: 2,
    notes: 'صفقة خروج ناجحة، الربح محقق ومغلق بالمستندات.',
    partners: [{ id: 'partner-001', name_ar: 'محمد أحمد الشريك', equity_pct: 100 }],
    transactions: [
      {
        id: 'txn-re-006',
        date: '2020-02-01',
        direction: 'expense',
        category_ar: 'شراء أصل',
        category_en: 'Asset acquisition',
        amount: 3_000_000,
        currency: 'EGP',
        amount_egp: 3_000_000,
        document_title: 'عقد شراء الأرض',
      },
      {
        id: 'txn-re-007',
        date: '2024-06-15',
        direction: 'income',
        category_ar: 'بيع أصل',
        category_en: 'Asset sale',
        amount: 6_500_000,
        currency: 'EGP',
        amount_egp: 6_500_000,
        document_title: 'عقد بيع الأرض',
      },
    ],
    obligations: [],
    documents: [
      { id: 'doc-re-007', title_ar: 'عقد شراء الأرض', type_ar: 'عقد', date: '2020-02-01' },
      { id: 'doc-re-008', title_ar: 'عقد بيع الأرض', type_ar: 'عقد بيع', date: '2024-06-15' },
    ],
  },
];

function sum(field: keyof Pick<RealEstateAssetDetail, 'acquisition_cost_egp' | 'development_cost_egp' | 'current_valuation_egp' | 'profit_loss_egp'>) {
  return realEstateAssets.reduce((total, asset) => total + asset[field], 0);
}

export const realEstateRows: AssetRowVM[] = realEstateAssets.map((asset) => ({
  id: asset.id,
  sector_id: asset.sector_id,
  project_name_ar: asset.project_name_ar,
  project_name_en: asset.project_name_en,
  name_ar: asset.name_ar,
  name_en: asset.name_en,
  type: asset.type,
  status: asset.status,
  location: asset.location,
  acquisition_cost_egp: asset.acquisition_cost_egp,
  development_cost_egp: asset.development_cost_egp,
  current_valuation_egp: asset.current_valuation_egp,
  sale_price_egp: asset.sale_price_egp,
  profit_loss_egp: asset.profit_loss_egp,
  profit_loss_pct: asset.profit_loss_pct,
  document_count: asset.document_count,
}));

export const realEstateKpis: KpiCardVM[] = [
  {
    id: 'asset-count',
    title_ar: 'عدد الأصول',
    title_en: 'Asset count',
    value: realEstateAssets.length,
    unit_ar: 'أصول',
    unit_en: 'assets',
    period_ar: 'كل الفترات',
    period_en: 'All time',
    trend_ar: 'أصول عقارية مسجلة على مستوى المحفظة',
    trend_en: 'Registered real estate portfolio assets',
    status: 'info',
    source_ar: 'سجل الأصول العقارية',
    source_en: 'Real estate asset register',
  },
  {
    id: 'acquisition-cost',
    title_ar: 'تكلفة الشراء',
    title_en: 'Acquisition cost',
    value: sum('acquisition_cost_egp'),
    currency: 'EGP',
    period_ar: 'كل الفترات',
    period_en: 'All time',
    trend_ar: 'رأس المال المدفوع للاستحواذ على الأصول',
    trend_en: 'Capital spent to acquire assets',
    status: 'neutral',
    source_ar: 'معاملات شراء الأصول',
    source_en: 'Asset acquisition transactions',
  },
  {
    id: 'development-cost',
    title_ar: 'تكلفة التطوير',
    title_en: 'Development CAPEX',
    value: sum('development_cost_egp'),
    currency: 'EGP',
    period_ar: 'كل الفترات',
    period_en: 'All time',
    trend_ar: 'مصروفات رأسمالية مرتبطة بالتطوير',
    trend_en: 'Capital expenditure tied to development',
    status: 'warning',
    source_ar: 'معاملات التطوير الرأسمالي',
    source_en: 'Development CAPEX transactions',
  },
  {
    id: 'valuation',
    title_ar: 'قيمة البيع / التقييم',
    title_en: 'Sale / valuation value',
    value: sum('current_valuation_egp'),
    currency: 'EGP',
    period_ar: 'آخر تقييم',
    period_en: 'Latest valuation',
    trend_ar: 'قيمة المحفظة حسب آخر بيع أو تقييم',
    trend_en: 'Portfolio value by latest sale or valuation',
    status: 'positive',
    source_ar: 'سجل التقييمات والمبيعات',
    source_en: 'Valuations and sales register',
  },
  {
    id: 'profit-loss',
    title_ar: 'صافي الربح / الخسارة',
    title_en: 'Net profit / loss',
    value: sum('profit_loss_egp'),
    currency: 'EGP',
    period_ar: 'كل الفترات',
    period_en: 'All time',
    trend_ar: 'التقييم/البيع ناقص الشراء والتطوير',
    trend_en: 'Valuation/sale minus acquisition and development',
    status: sum('profit_loss_egp') >= 0 ? 'positive' as StatusTone : 'negative' as StatusTone,
    source_ar: 'محرك ربحية الأصول',
    source_en: 'Asset profitability engine',
  },
  {
    id: 'under-development',
    title_ar: 'أصول تحت التطوير',
    title_en: 'Assets under development',
    value: realEstateAssets.filter((asset) => asset.status === 'under_development').length,
    unit_ar: 'أصول',
    unit_en: 'assets',
    period_ar: 'حاليًا',
    period_en: 'Current',
    trend_ar: 'تحتاج متابعة CAPEX وتراخيص',
    trend_en: 'Needs CAPEX and permit follow-up',
    status: 'warning',
    source_ar: 'حالة الأصول',
    source_en: 'Asset status',
  },
];

export function findRealEstateAsset(id: string) {
  return realEstateAssets.find((asset) => asset.id === id) ?? null;
}

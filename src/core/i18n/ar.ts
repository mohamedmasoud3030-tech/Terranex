/**
 * Arabic translation strings — primary language for Terranex.
 * All keys must exist in both ar.ts and en.ts (enforced by TranslationMap type).
 */
export const ar = {
  // App shell
  app_name: 'Terranex',
  app_tagline: 'نظام التشغيل الاستثماري',
  env_badge: 'بيئة تطوير',

  // Navigation
  nav_dashboard: 'لوحة القيادة',
  nav_real_estate: 'العقاري',
  nav_agriculture: 'الزراعي',
  nav_livestock: 'الحيواني',
  nav_finance: 'المالية',
  nav_documents: 'المستندات',
  nav_partners: 'الشركاء',
  nav_settings: 'الإعدادات',

  // Dashboard
  dashboard_title: 'أين تقف الشركة ماليًا وتشغيليًا الآن؟',
  dashboard_description: 'مؤشرات موحدة بالجنيه المصري تغطي القطاعات والمشاريع والالتزامات والأصول.',
  dashboard_period_label: 'نطاق العرض',
  dashboard_period_note: 'كل رقم مالي يظهر مع الفترة والعملة ومصدر السجل.',

  // Sectors
  sector_real_estate_name: 'الاستثمار العقاري',
  sector_real_estate_desc: 'أراضي، أصول، شراء، تطوير، بيع، مستندات ملكية وربحية.',
  sector_agriculture_name: 'الاستثمار الزراعي',
  sector_agriculture_desc: 'مزارع، محاصيل، مواسم، إنتاج، مصروفات ومبيعات.',
  sector_livestock_name: 'الاستثمار الحيواني',
  sector_livestock_desc: 'قطعان، أعلاف، علاج، تحصينات، ولادات، نفوق ومبيعات.',
  sector_finance_name: 'المالية والالتزامات',
  sector_finance_desc: 'إيرادات، مصروفات، ذمم مدينة، ذمم دائنة، وربط بالمستندات.',
  sector_open_record: 'فتح سجل القطاع',
  sector_status_active: 'نشط',
  sector_status_review: 'يحتاج مراجعة',
  sector_status_stable: 'مستقر',
  sector_status_inactive: 'غير نشط',

  // KPIs
  kpi_total_assets: 'إجمالي الأصول',
  kpi_total_expenses: 'إجمالي المصروفات',
  kpi_total_revenue: 'إجمالي الإيرادات',
  kpi_net_profit: 'صافي الربح / الخسارة',
  kpi_open_receivables: 'الذمم المدينة المفتوحة',
  kpi_open_payables: 'الذمم الدائنة المفتوحة',

  // Obligations table
  obligations_title: 'الذمم والالتزامات القريبة',
  obligations_description: 'يربط كل سجل بالمال والقطاع والطرف والمستند.',
  col_date: 'التاريخ',
  col_type: 'النوع',
  col_sector: 'القطاع',
  col_party: 'الطرف',
  col_amount: 'المبلغ',
  col_status: 'الحالة',
  col_document: 'المستند',
  col_project: 'المشروع',
  col_direction: 'الاتجاه',
  col_category: 'الفئة',

  // Obligation directions
  direction_receivable: 'ذمة مدينة',
  direction_payable: 'ذمة دائنة',

  // Obligation statuses
  status_open: 'مستحق',
  status_partial: 'جزئي',
  status_settled: 'مدفوع',
  status_disputed: 'متنازع عليه',
  status_written_off: 'مشطوب',

  // Transaction directions
  transaction_income: 'إيراد',
  transaction_expense: 'مصروف',

  // Period filter
  period_month: 'الشهر الحالي',
  period_quarter: 'الربع الحالي',
  period_year: 'السنة الحالية',
  period_all: 'كل الفترات',
  period_custom: 'فترة مخصصة',

  // Actions
  action_add_record: 'إضافة سجل جديد',
  action_view_all: 'عرض الكل',
  action_export: 'تصدير',
  action_filter: 'تصفية',
  action_search: 'ابحث عن أصل، موسم، قطيع أو مستند',
  action_save: 'حفظ',
  action_cancel: 'إلغاء',
  action_delete: 'حذف',
  action_edit: 'تعديل',
  action_close: 'إغلاق',
  action_retry: 'إعادة المحاولة',

  // States
  state_loading: 'جار التحميل…',
  state_empty_title: 'لا توجد بيانات بعد',
  state_empty_description: 'أضف أول سجل لهذا القسم لتبدأ.',
  state_error_title: 'خطأ في تحميل البيانات',
  state_error_description: 'تعذّر تحميل البيانات. يرجى المحاولة مجددًا.',
  state_no_documents: 'لا توجد مستندات مرتبطة بعد',
  state_no_documents_desc: 'ارفع أو اربط مستندًا بهذا السجل.',

  // Profitability
  profit_label: 'الربحية',
  profit_income: 'الإيرادات الكلية',
  profit_expense: 'المصروفات الكلية',
  profit_gross: 'إجمالي الربح',
  profit_obligations: 'الالتزامات المفتوحة',
  profit_net: 'صافي الربح',
  profit_formula: 'صافي الربح = الإيرادات − المصروفات − الالتزامات المفتوحة',

  // Currencies
  currency_EGP: 'جنيه مصري',
  currency_USD: 'دولار أمريكي',
  currency_SAR: 'ريال سعودي',
  currency_AED: 'درهم إماراتي',
  currency_EUR: 'يورو',
  currency_GBP: 'جنيه إسترليني',

  // Validation
  validation_required: 'هذا الحقل مطلوب',
  validation_invalid_number: 'أدخل رقمًا صحيحًا',
  validation_invalid_date: 'أدخل تاريخًا صحيحًا',
  validation_equity_exceeds_100: 'مجموع نسب الملكية يتجاوز 100%',
  validation_min_zero: 'القيمة لا تقل عن صفر',
} as const;

export type TranslationKey = keyof typeof ar;

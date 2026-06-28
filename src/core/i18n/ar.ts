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
  currency_OMR: 'ريال عُماني',
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

  // Projects
  nav_projects: 'المشاريع',
  projects_title: 'إدارة المشاريع',
  projects_description: 'كل مشروع هو حاوية الأصول والمعاملات والمستندات والشركاء.',
  project_new: 'مشروع جديد',
  project_name_ar: 'اسم المشروع (عربي)',
  project_name_en: 'اسم المشروع (إنجليزي)',
  project_sector: 'القطاع',
  project_status: 'الحالة',
  project_start_date: 'تاريخ البدء',
  project_end_date: 'تاريخ الانتهاء (اختياري)',
  project_currency: 'العملة الأساسية',
  project_description_ar: 'وصف المشروع',
  project_status_planning: 'تخطيط',
  project_status_active: 'نشط',
  project_status_on_hold: 'متوقف مؤقتاً',
  project_status_completed: 'مكتمل',
  project_status_cancelled: 'ملغى',
  project_profitability: 'ربحية المشروع',
  project_transactions: 'المعاملات',
  project_assets: 'الأصول',
  project_documents: 'المستندات',
  project_partners_equity: 'شركاء الملكية',

  // Assets
  assets_title: 'الأصول',
  asset_new: 'أصل جديد',
  asset_name_ar: 'اسم الأصل',
  asset_type: 'نوع الأصل',
  asset_acquisition_date: 'تاريخ الاقتناء',
  asset_acquisition_cost: 'تكلفة الاقتناء',
  asset_current_value: 'القيمة الحالية',
  asset_status: 'حالة الأصل',
  asset_quantity: 'الكمية',
  asset_unit: 'الوحدة',
  asset_type_land: 'أرض',
  asset_type_building: 'مبنى',
  asset_type_farm: 'مزرعة',
  asset_type_equipment: 'معدات',
  asset_type_herd: 'قطيع',
  asset_type_animal_group: 'مجموعة حيوانات',
  asset_type_crop: 'محصول',
  asset_type_other: 'أخرى',
  asset_status_owned: 'مملوك',
  asset_status_leased: 'مستأجر',
  asset_status_sold: 'مباع',
  asset_status_disposed: 'مُتخلص منه',

  // Partners
  partners_title: 'الشركاء والأطراف',
  partner_new: 'شريك / طرف جديد',
  partner_name_ar: 'الاسم (عربي)',
  partner_category: 'التصنيف',
  partner_role: 'الدور',
  partner_category_equity: 'شريك ملكية',
  partner_category_counterparty: 'طرف تعامل',
  partner_role_supplier: 'مورد',
  partner_role_client: 'عميل',
  partner_role_service: 'مزود خدمة',
  partner_role_lender: 'ممول',
  partner_role_government: 'جهة حكومية',
  partner_role_other: 'أخرى',

  // Documents
  documents_title: 'إدارة المستندات',
  document_new: 'مستند جديد',
  document_title_ar: 'عنوان المستند',
  document_type: 'نوع المستند',
  document_issue_date: 'تاريخ الإصدار',
  document_expiry_date: 'تاريخ الانتهاء',
  document_type_contract: 'عقد',
  document_type_invoice: 'فاتورة',
  document_type_receipt: 'إيصال',
  document_type_deed: 'صك ملكية',
  document_type_vet: 'سجل بيطري',
  document_type_sales: 'عقد بيع',
  document_type_permit: 'تصريح',
  document_type_court: 'وثيقة قضائية',
  document_type_other: 'أخرى',

  // Transactions
  transactions_title: 'سجل المعاملات',
  transaction_new: 'معاملة جديدة',
  transaction_date: 'التاريخ',
  transaction_direction: 'الاتجاه',
  transaction_category: 'التصنيف',
  transaction_amount: 'المبلغ',
  transaction_currency: 'العملة',
  transaction_fx_rate: 'سعر الصرف (إلى EGP)',
  transaction_counterparty: 'الطرف',
  transaction_document: 'المستند المرتبط',
  transaction_notes: 'ملاحظات',
  transaction_direction_income: 'إيراد',
  transaction_direction_expense: 'مصروف',

  // Obligations
  obligations_new: 'التزام جديد',
  obligation_direction_receivable: 'ذمة مدينة (لنا)',
  obligation_direction_payable: 'ذمة دائنة (علينا)',
  obligation_status_open: 'مفتوح',
  obligation_status_partial: 'مسدد جزئياً',
  obligation_status_settled: 'مسدد',
  obligation_status_disputed: 'متنازع عليه',
  obligation_status_written_off: 'مشطوب',
  obligation_due_date: 'تاريخ الاستحقاق',
  obligation_settle: 'تسجيل دفعة',
  obligation_settle_amount: 'مبلغ التسوية (EGP)',

  // Profitability extended
  profitability_title: 'محرك الربحية',
  profitability_desc: 'الربح = Σ الإيرادات − Σ المصروفات — قابل للتتبع حتى كل معاملة ومستند',
  profitability_margin: 'هامش الربح',
  profitability_by_sector: 'الربحية بالقطاع',
  profitability_by_project: 'الربحية بالمشروع',
  profitability_partner_splits: 'حصص الشركاء',

  // Operational Events — ADR-003
  nav_events: 'الأحداث التشغيلية',
  events_title: 'الأحداث التشغيلية',
  events_description: 'تتبع تشغيلي حي — ولادات، نفوق، تحصينات، حصاد — مربوط بالأصول والمشاريع.',
  events_new: 'حدث جديد',
  events_new_title: 'تسجيل حدث تشغيلي',
  events_type: 'نوع الحدث',
  events_weight_kg: 'الوزن (كجم)',
  events_cost_egp: 'التكلفة (EGP)',
  events_count: 'حدث',
  events_live_balances: 'الأرصدة الحية',
  events_from_events: 'من الأحداث',
  events_choose_asset: 'اختر الأصل…',
  events_choose_project: 'اختر المشروع…',
} as const;

export type TranslationKey = keyof typeof ar;

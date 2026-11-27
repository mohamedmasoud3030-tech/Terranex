/**
 * Plain-language layer — every simplified sentence lives here once.
 *
 * The product speaks precise operational Arabic, which reads as accounting
 * jargon to a first-time owner who is not an accountant. This module holds
 * the plain-words register: what a page is for, what the current step is,
 * and what to do next. Pages reference these keys; nobody rewrites the
 * sentences inline, so the plain register stays consistent and single-sourced.
 *
 * Register rules (guarded by tests/plain-language.test.ts):
 *   - one sentence per intro, no accounting terms (قيود، التزامات، ذمم، …)
 *   - no internal roadmap codes (R14, BD-003, …) and no English schema codes
 *   - friendly but professional Modern Standard Arabic, Egyptian-market tone
 */

/** The first-run journey: organization → first project → record its data. */
export const JOURNEY_STEPS = [
  {
    id: 'organization',
    title: 'أنشئ حساب شركتك',
    plain: 'خطوة واحدة فقط: اكتب اسم شركتك أو نشاطك، وسيُفتح لك حسابك الخاص.',
  },
  {
    id: 'project',
    title: 'أضف أول مشروع',
    plain: 'المشروع هو الصفقة التي تريد متابعة أموالها: عقار، مزرعة، أو قطيع.',
  },
  {
    id: 'record',
    title: 'سجّل بيانات المشروع',
    plain: 'أدخل ما دفعته وما قبضته خطوة خطوة، والنظام يرتّب الحسابات لك.',
  },
] as const;

export type JourneyStepId = (typeof JOURNEY_STEPS)[number]['id'];

/**
 * One-line plain explanation shown at the top of each major page.
 * Keyed by a stable page key, never by route, so a route rename cannot
 * silently drop the explanation.
 */
export const PAGE_INTROS = {
  home: 'من هنا ترى صورة شركتك كاملة: أموالك، مشاريعك، وما يحتاج انتباهك اليوم.',
  projects: 'كل مشاريعك في مكان واحد: افتح مشروعًا لمتابعته أو أنشئ مشروعًا جديدًا.',
  'projects-new': 'أنشئ مشروعًا جديدًا بثلاث معلومات فقط: نوعه واسمه ووصف اختياري.',
  portfolios: 'المحافظ طريقة لتجميع مشاريعك تحت عناوين تسهّل المتابعة، ويمكنك العمل بدونها في البداية.',
  'portfolios-new': 'أنشئ محفظة باسم واضح ثم أضف مشاريعك إليها لاحقًا متى شئت.',
  assets: 'كل ما تملكه مشاريعك من عقارات وأراضٍ وقطعان، وأداء كل منها.',
  documents: 'ارفع عقودك وأوراقك المهمة هنا لتبقى محفوظة ومرتبطة بمشروعك.',
  inventory: 'ما لديك من مخزون، مثل المحاصيل المخزنة والمواد، وأين يوجد.',
  invoices: 'فواتير الموردين التي عليك دفعها، وحالة كل فاتورة بوضوح.',
  journal: 'سجل تلقائي بكل حركة مالية في مشاريعك، لا تحتاج إلى تعديله بنفسك.',
  transactions: 'حركات حساباتك البنكية: ما دخل وما خرج، يومًا بيوم.',
  vat: 'متابعة الضريبة على مشترياتك ومبيعاتك من مكان واحد.',
  reports: 'تقارير جاهزة عن أداء شركتك، تصلح للاطلاع والمشاركة.',
  settings: 'إعدادات حسابك وشركتك والمظهر.',
  intake: 'مسار مرتّب يمشي معك خطوة بخطوة لتسجيل بيانات مشروعك من البداية.',
  'project-intake':
    'سجّل بيانات مشروعك الأساسية خطوة بخطوة، ويمكنك التوقف والعودة في أي وقت.',
  'project-agriculture': 'هذه مساحة مزرعتك: سجّل حقولك ومحاصيلك وحصادك ومبيعاتك من هنا.',
  'project-livestock': 'هذه مساحة قطيعك: سجّل مواقعك وقطعانك وعملياتها اليومية من هنا.',
} as const;

export type PageIntroKey = keyof typeof PAGE_INTROS;

/** Onboarding (organization creation) copy. */
export const ONBOARDING_COPY = {
  title: 'أهلًا بك في تيرانكس',
  plain:
    'سنمشي معًا ثلاث خطوات بسيطة: ننشئ حساب شركتك، ثم أول مشروع، ثم نبدأ تسجيل بياناته. لا تحتاج أي خبرة محاسبية.',
  nameLabel: 'اسم الشركة أو النشاط',
  namePlaceholder: 'مثال: شركة النيل للاستثمار',
  nameHint: 'سيُسجَّل هذا الاسم على حسابك بصلاحية المالك الكاملة، ويمكنك تغييره لاحقًا من الإعدادات.',
  submit: 'إنشاء المنظمة',
  pending: 'جارٍ الإنشاء…',
  afterNote: 'بعد الضغط على الزر سننتقل مباشرة إلى الخطوة الثانية: إضافة أول مشروع.',
} as const;

/** Project creation copy: sectors explained in everyday words. */
export const PROJECT_FORM_COPY = {
  title: 'أضف أول مشروع',
  plain: 'المشروع هو الصفقة التي تتابع أموالها منفصلة عن غيرها. اختر نوعه، واكتب اسمه، واترك الباقي لنا.',
  defaultsNote: 'سيبدأ مشروعك كمسودة وبالجنيه المصري، وهي الحالة الآمنة لأي مشروع جديد.',
  sectorLegend: 'نوع المشروع',
  nameLabel: 'اسم المشروع',
  namePlaceholder: 'مثال: عمارة المعادي، مزرعة الوادي، قطيع التسمين الأول',
  referenceLabel: 'رقم أو اسم مختصر للرجوع إليه',
  referenceHint: 'اختياري — يساعدك على التمييز بين مشاريعك لاحقًا.',
  descriptionLabel: 'وصف قصير',
  descriptionHint: 'اختياري — جملة واحدة تذكّرك بما يخص هذا المشروع.',
} as const;

export const SECTOR_PLAIN: Record<string, string> = {
  REAL_ESTATE: 'شقق أو محلات أو أراضٍ تشتريها ثم تبيعها أو تؤجرها. بعد الإنشاء سنفتح لك مسار التسجيل الموجّه.',
  AGRICULTURE: 'أرض زراعية ومحاصيل تزرعها وتبيع حصادها. بعد الإنشاء سنفتح لك مساحة الزراعة مباشرة.',
  LIVESTOCK: 'مواشي أو دواجن تربيها وتبيعها بعد التسمين أو الإنتاج. بعد الإنشاء سنفتح لك مساحة الثروة الحيوانية مباشرة.',
};

/** "What to do next" prompts, keyed by situation. */
export const NEXT_STEP_COPY = {
  createFirstProject: {
    title: 'ما الخطوة التالية؟',
    description: 'أنشئ أول مشروع لك — يستغرق أقل من دقيقة، ولا تحتاج سوى اسمه ونوعه.',
    actionLabel: 'أنشئ أول مشروع',
  },
  continueIntake: {
    title: 'ما الخطوة التالية؟',
    actionLabel: 'اذهب إلى الخطوة',
  },
  intakeDone: {
    title: 'كل الخطوات الأساسية مكتملة',
    description: 'بيانات مشروعك الأساسية جاهزة. يمكنك الآن متابعة العمل اليومي من مساحة المشروع.',
    actionLabel: 'افتح مساحة المشروع',
  },
} as const;

/**
 * Words a non-accountant should never have to read in the plain layer.
 * The guard test fails if any intro or step copy contains one of them.
 */
export const JARGON_BLOCKLIST = [
  'قيد',
  'قيود',
  'التزام',
  'ذمم',
  'استحقاق',
  'مطابقة',
  'إقفال',
  'إيراد معترف',
  'مصروف مُعلن',
  'تجميع عملات',
  'سعر صرف',
  'مخصومة',
  'رأس المال المساهم',
  'R14',
  'BD-',
];

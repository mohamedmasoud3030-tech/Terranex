import type { ConditionalSectionCode } from './schema';

export const INTAKE_GROUPS = [
  'PROJECT_SETUP',
  'INVESTORS_AND_TERMS',
  'CAPITAL_HISTORY',
  'BANK_AND_CASH',
  'PROPERTY',
  'OPENING_POSITION',
  'VALIDATION_AND_RECONCILIATION',
] as const;

export type IntakeGroupId = (typeof INTAKE_GROUPS)[number];

export const INTAKE_SECTION_CODES = [
  'DS01_ORGANIZATION',
  'DS02_PROJECT',
  'FREEZE_DATE',
  'DS03_PARTIES',
  'DS04_AGREEMENT',
  'DS05_COMMITMENTS',
  'DS06_HISTORICAL_CALLS',
  'DS07_HISTORICAL_CONTRIBUTIONS',
  'DS08_CASH_ACCOUNTS',
  'DS16_BANK_STATEMENTS',
  'ACCOUNTING_PERIOD',
  'DS11_PROPERTY',
  'DS12_ACQUISITION',
  'DS13_DEVELOPMENT',
  'CONTROL_TOTALS',
  'DS09_OPENING_BALANCES',
  'DS10_UNPAID_SUPPLIERS',
  'DS14_SALES',
  'DS15_DISTRIBUTIONS',
  'OPENING_VALIDATION',
  'OPENING_APPROVAL',
  'OPENING_POSTING',
  'OPENING_RECONCILIATION',
  'DS17_EVIDENCE',
  'READINESS_RESULT',
] as const;

export type IntakeSectionCode = (typeof INTAKE_SECTION_CODES)[number];

export type SectionKind = 'MANDATORY' | 'CONDITIONAL' | 'DERIVED';

export type SectionStatus =
  | 'COMPLETE'
  | 'MISSING'
  | 'CONDITIONAL_OPEN'
  | 'NOT_APPLICABLE'
  | 'BLOCKED'
  | 'IN_PROGRESS'
  | 'FAILED';

export type OpeningImportStatus =
  | 'DRAFT'
  | 'VALIDATED'
  | 'READY_FOR_APPROVAL'
  | 'APPROVED'
  | 'POSTED'
  | 'REJECTED'
  | 'FAILED';

export type ReadinessVerdict =
  | 'READY_TO_RECEIVE_REAL_DATA'
  | 'INTAKE_IN_PROGRESS'
  | 'OPENING_BLOCKED'
  | 'OPENING_READY_TO_STAGE'
  | 'OPENING_IN_PROGRESS'
  | 'OPENING_POSTED_AWAITING_RECONCILIATION'
  | 'OPENING_RECONCILED_PENDING_REAL_EVIDENCE';

export type IntakeSnapshot = {
  organizationName: string | null;
  projectName: string | null;
  reportingCurrency: string | null;
  freezeDate: string | null;
  freezeEvidenceReference: string | null;
  organizationEvidenceReference: string | null;
  projectEvidenceReference: string | null;
  agreementTitleOrReference: string | null;
  declaredDebitTotal: string | null;
  declaredCreditTotal: string | null;
  investorCount: number;
  activeAgreement: boolean;
  agreementEffectiveDate: string | null;
  commitmentCount: number;
  allocationRulesConfigured: boolean;
  issuedCallCount: number;
  contributionCount: number;
  contributionCashAttributedCount: number;
  cashAccountCount: number;
  bankStatementLineCount: number;
  openPeriodCoversFreeze: boolean;
  openPeriodExists: boolean;
  realEstateProfile: boolean;
  realEstateStrategy: string | null;
  assetCount: number;
  parcelCount: number;
  acquisitionCount: number;
  approvedBudgetCount: number;
  openingImportStatus: OpeningImportStatus | null;
  openingRejectedRowCount: number;
  openingControlTotalsMatch: boolean | null;
  openingIsReversed: boolean;
  openingMappingCodes: string[];
  openingDebitVariance: string | null;
  openingCreditVariance: string | null;
  matchedZeroVarianceCheckpoints: number;
  nonZeroVarianceCheckpoints: number;
  openCriticalExceptions: number;
  evidenceItemCount: number;
  openModellingGapCount: number;
  applicability: Partial<Record<ConditionalSectionCode, boolean>>;
};

export type IntakeSection = {
  code: IntakeSectionCode;
  group: IntakeGroupId;
  kind: SectionKind;
  status: SectionStatus;
  titleAr: string;
  summaryAr: string;
  blockingReasons: string[];
  warnings: string[];
};

export type IntakeReadiness = {
  sections: IntakeSection[];
  groups: Array<{
    id: IntakeGroupId;
    titleAr: string;
    complete: number;
    total: number;
    hasFailure: boolean;
    next: boolean;
  }>;
  nextSection: IntakeSectionCode | null;
  mandatoryMissing: IntakeSectionCode[];
  failures: IntakeSectionCode[];
  openModellingGaps: number;
  verdict: ReadinessVerdict;
  verdictAr: string;
  phase2Passed: false;
  phase2ReasonAr: string;
};

const GROUP_TITLE: Record<IntakeGroupId, string> = {
  PROJECT_SETUP: 'إعداد المشروع',
  INVESTORS_AND_TERMS: 'المستثمرون والشروط',
  CAPITAL_HISTORY: 'تاريخ رأس المال',
  BANK_AND_CASH: 'البنك والنقدية',
  PROPERTY: 'العقار',
  OPENING_POSITION: 'المركز الافتتاحي',
  VALIDATION_AND_RECONCILIATION: 'التحقق والمطابقة',
};

const TITLE: Record<IntakeSectionCode, string> = {
  DS01_ORGANIZATION: 'المنظمة',
  DS02_PROJECT: 'المشروع الاستثماري',
  FREEZE_DATE: 'تاريخ التجميد',
  DS03_PARTIES: 'الأطراف والمستثمرون',
  DS04_AGREEMENT: 'الاتفاقية الحاكمة',
  DS05_COMMITMENTS: 'الالتزامات الرأسمالية',
  DS06_HISTORICAL_CALLS: 'طلبات رأس المال التاريخية',
  DS07_HISTORICAL_CONTRIBUTIONS: 'المساهمات التاريخية',
  DS08_CASH_ACCOUNTS: 'حسابات المشروع النقدية',
  DS16_BANK_STATEMENTS: 'كشوف الحساب البنكي',
  ACCOUNTING_PERIOD: 'الفترة المحاسبية المفتوحة',
  DS11_PROPERTY: 'الأصول والقطع',
  DS12_ACQUISITION: 'أساس الاستحواذ',
  DS13_DEVELOPMENT: 'ميزانية التطوير المعتمدة',
  CONTROL_TOTALS: 'المجاميع الرقابية الموقعة',
  DS09_OPENING_BALANCES: 'الأرصدة الافتتاحية',
  DS10_UNPAID_SUPPLIERS: 'التزامات الموردين غير المسددة',
  DS14_SALES: 'مبيعات وتصرفات ما قبل التجميد',
  DS15_DISTRIBUTIONS: 'توزيعات معتمدة غير مدفوعة',
  OPENING_VALIDATION: 'التحقق من الاستيراد',
  OPENING_APPROVAL: 'اعتماد الاستيراد',
  OPENING_POSTING: 'ترحيل القيد الافتتاحي',
  OPENING_RECONCILIATION: 'المطابقة الصفرية',
  DS17_EVIDENCE: 'سجل الأدلة',
  READINESS_RESULT: 'نتيجة الجاهزية',
};

const APPLICABILITY_BY_SECTION: Partial<Record<IntakeSectionCode, ConditionalSectionCode>> = {
  DS06_HISTORICAL_CALLS: 'HISTORICAL_CALLS',
  DS07_HISTORICAL_CONTRIBUTIONS: 'HISTORICAL_CONTRIBUTIONS',
  DS12_ACQUISITION: 'ACQUISITION_BASIS',
  DS13_DEVELOPMENT: 'DEVELOPMENT_BASELINE',
  DS10_UNPAID_SUPPLIERS: 'UNPAID_SUPPLIERS',
  DS14_SALES: 'SALES_DISPOSITIONS',
  DS15_DISTRIBUTIONS: 'HISTORICAL_DISTRIBUTIONS',
  DS16_BANK_STATEMENTS: 'BANK_STATEMENTS',
};

function zero(value: string | null | undefined): boolean {
  return value === null || value === undefined || value === '0';
}

function applicabilityOf(
  snapshot: IntakeSnapshot,
  code: IntakeSectionCode,
): boolean | undefined {
  const key = APPLICABILITY_BY_SECTION[code];
  return key ? snapshot.applicability[key] : undefined;
}

function section(
  code: IntakeSectionCode,
  group: IntakeGroupId,
  kind: SectionKind,
  status: SectionStatus,
  summaryAr: string,
  blockingReasons: string[] = [],
  warnings: string[] = [],
): IntakeSection {
  return {
    code,
    group,
    kind,
    status,
    titleAr: TITLE[code],
    summaryAr,
    blockingReasons,
    warnings,
  };
}

function evaluate(snapshot: IntakeSnapshot): IntakeSection[] {
  const sections: IntakeSection[] = [];

  sections.push(snapshot.organizationName
    ? section('DS01_ORGANIZATION', 'PROJECT_SETUP', 'MANDATORY', 'COMPLETE',
      `المنظمة «${snapshot.organizationName}» · العملة الوظيفية جنيه مصري.`,
      [],
      snapshot.organizationEvidenceReference ? [] : ['سجّل مرجع السجل التجاري في سجل الأدلة.'])
    : section('DS01_ORGANIZATION', 'PROJECT_SETUP', 'MANDATORY', 'MISSING',
      'أنشئ المنظمة أولًا. العملة الوظيفية ثابتة: جنيه مصري.',
      ['المنظمة غير مُنشأة.']));

  sections.push(snapshot.projectName
    ? section('DS02_PROJECT', 'PROJECT_SETUP', 'MANDATORY', 'COMPLETE',
      `المشروع «${snapshot.projectName}» · قطاع عقاري · ${snapshot.reportingCurrency ?? 'EGP'}.`,
      [],
      snapshot.projectEvidenceReference ? [] : ['سجّل مرجع نطاق المشروع التجريبي.'])
    : section('DS02_PROJECT', 'PROJECT_SETUP', 'MANDATORY',
      snapshot.organizationName ? 'MISSING' : 'BLOCKED',
      'أنشئ مشروعًا عقاريًا واحدًا على الأقل داخل المنظمة.',
      [snapshot.organizationName ? 'المشروع غير مُنشأ.' : 'أنشئ المنظمة أولًا.']));

  sections.push(snapshot.freezeDate
    ? section('FREEZE_DATE', 'PROJECT_SETUP', 'MANDATORY', 'COMPLETE',
      `تاريخ التجميد ${snapshot.freezeDate}. كل الأرصدة تُدخل كما في نهاية هذا اليوم.`)
    : section('FREEZE_DATE', 'PROJECT_SETUP', 'MANDATORY',
      snapshot.projectName ? 'MISSING' : 'BLOCKED',
      'اتفق مع مالك العميل على تاريخ تجميد واحد قبل قبول أي رصيد.',
      [snapshot.projectName ? 'تاريخ التجميد غير مسجّل.' : 'أنشئ المشروع أولًا.']));

  const canAddInvestors = Boolean(snapshot.projectName);
  sections.push(snapshot.investorCount > 0
    ? section('DS03_PARTIES', 'INVESTORS_AND_TERMS', 'MANDATORY', 'COMPLETE',
      `${snapshot.investorCount} مستثمر. الطرف يُنشأ مرة واحدة ويُعاد استخدامه.`)
    : section('DS03_PARTIES', 'INVESTORS_AND_TERMS', 'MANDATORY',
      canAddInvestors ? 'MISSING' : 'BLOCKED',
      'أضف المستثمرين كما وردوا في الاتفاقية الحاكمة.',
      [canAddInvestors ? 'لا يوجد مستثمرون في المشروع.' : 'أنشئ المشروع أولًا.']));

  const canDraftAgreement = snapshot.investorCount > 0;
  if (!snapshot.activeAgreement) {
    sections.push(section('DS04_AGREEMENT', 'INVESTORS_AND_TERMS', 'MANDATORY',
      canDraftAgreement ? 'MISSING' : 'BLOCKED',
      'فعّل نسخة اتفاقية حاكمة بتاريخ سريان، وعنوان/مرجع، وأوزان ملكية مجموعها 100٪.',
      [canDraftAgreement ? 'لا توجد اتفاقية مفعّلة.' : 'أضف مستثمرًا واحدًا على الأقل.']));
  } else if (!snapshot.agreementTitleOrReference || !snapshot.allocationRulesConfigured) {
    const reasons: string[] = [];
    if (!snapshot.agreementTitleOrReference) reasons.push('عنوان الاتفاقية أو مرجعها غير مسجّل.');
    if (!snapshot.allocationRulesConfigured) reasons.push('أوزان الملكية/التخصيص غير مثبتة على 100٪.');
    sections.push(section('DS04_AGREEMENT', 'INVESTORS_AND_TERMS', 'MANDATORY', 'IN_PROGRESS',
      `نسخة حاكمة سارية من ${snapshot.agreementEffectiveDate ?? '—'}. أكمل العنوان وأوزان الملكية.`,
      reasons));
  } else {
    sections.push(section('DS04_AGREEMENT', 'INVESTORS_AND_TERMS', 'MANDATORY', 'COMPLETE',
      `الاتفاقية «${snapshot.agreementTitleOrReference}» سارية من ${snapshot.agreementEffectiveDate}. أوزان الملكية مثبتة.`));
  }

  if (!snapshot.activeAgreement) {
    sections.push(section('DS05_COMMITMENTS', 'INVESTORS_AND_TERMS', 'MANDATORY', 'BLOCKED',
      'الالتزام مبلغ متفق عليه، وليس نقدًا مستلمًا.',
      ['فعّل الاتفاقية أولًا.']));
  } else if (snapshot.commitmentCount < snapshot.investorCount || snapshot.commitmentCount === 0) {
    sections.push(section('DS05_COMMITMENTS', 'INVESTORS_AND_TERMS', 'MANDATORY', 'MISSING',
      'أدخل التزامًا موجبًا لكل مشارك بالوحدات الصغرى للجنيه.',
      ['عدد الالتزامات لا يغطي كل المستثمرين.']));
  } else {
    sections.push(section('DS05_COMMITMENTS', 'INVESTORS_AND_TERMS', 'MANDATORY', 'COMPLETE',
      `${snapshot.commitmentCount} التزامًا. الالتزام ≠ المطلوب ≠ المساهمة.`));
  }

  const callsApplicable = applicabilityOf(snapshot, 'DS06_HISTORICAL_CALLS');
  if (!snapshot.activeAgreement) {
    sections.push(section('DS06_HISTORICAL_CALLS', 'CAPITAL_HISTORY', 'CONDITIONAL', 'BLOCKED',
      'الطلبات التاريخية تُدخل فقط إذا صدرت قبل تاريخ التجميد.',
      ['فعّل الاتفاقية أولًا.']));
  } else if (callsApplicable === false) {
    sections.push(section('DS06_HISTORICAL_CALLS', 'CAPITAL_HISTORY', 'CONDITIONAL', 'NOT_APPLICABLE',
      'صرّح المشغّل بأنه لا توجد طلبات رأس مال تاريخية.'));
  } else if (snapshot.issuedCallCount > 0) {
    sections.push(section('DS06_HISTORICAL_CALLS', 'CAPITAL_HISTORY', 'CONDITIONAL', 'COMPLETE',
      `${snapshot.issuedCallCount} طلبًا مُصدرًا.`));
  } else {
    sections.push(section('DS06_HISTORICAL_CALLS', 'CAPITAL_HISTORY', 'CONDITIONAL', 'CONDITIONAL_OPEN',
      'إن وُجدت إخطارات طلب قبل التجميد فأدخلها هنا، وإلا صرّح بأنها لا تنطبق.'));
  }

  const contribApplicable = applicabilityOf(snapshot, 'DS07_HISTORICAL_CONTRIBUTIONS');
  const doubleCount = snapshot.contributionCount > 0
    && snapshot.openingMappingCodes.includes('OPENING_CONTRIBUTED_CAPITAL');
  if (!snapshot.activeAgreement) {
    sections.push(section('DS07_HISTORICAL_CONTRIBUTIONS', 'CAPITAL_HISTORY', 'CONDITIONAL', 'BLOCKED',
      'المساهمة أثر نقدي مستقل عن الالتزام وعن الطلب.',
      ['فعّل الاتفاقية أولًا.']));
  } else if (contribApplicable === false) {
    sections.push(section('DS07_HISTORICAL_CONTRIBUTIONS', 'CAPITAL_HISTORY', 'CONDITIONAL', 'NOT_APPLICABLE',
      'صرّح المشغّل بأنه لا توجد مساهمات تاريخية عبر مسار التمويل.'));
  } else if (doubleCount) {
    sections.push(section('DS07_HISTORICAL_CONTRIBUTIONS', 'CAPITAL_HISTORY', 'CONDITIONAL', 'FAILED',
      'المساهمة التاريخية لا تُكرَّر بين مسار التمويل ومسار النقدية الافتتاحية.',
      ['اختَر مسارًا واحدًا لكل أثر نقدي: تمويل (S1/S2) أو رصيد افتتاحي (S7)، لا الاثنين.']));
  } else if (snapshot.contributionCount > 0) {
    sections.push(section('DS07_HISTORICAL_CONTRIBUTIONS', 'CAPITAL_HISTORY', 'CONDITIONAL', 'COMPLETE',
      `${snapshot.contributionCount} مساهمة. لا تُسند نقديًا إن كان الأثر داخل الرصيد الافتتاحي.`,
      [],
      snapshot.contributionCashAttributedCount > 0
        ? ['وُجد إسناد نقدي لمساهمة. تأكد أنه ليس مكررًا مع نقدية افتتاحية.']
        : []));
  } else {
    sections.push(section('DS07_HISTORICAL_CONTRIBUTIONS', 'CAPITAL_HISTORY', 'CONDITIONAL', 'CONDITIONAL_OPEN',
      'إن استُلمت مساهمات قبل التجميد فأدخلها هنا أو عبّر عنها في الرصيد الافتتاحي، لا الاثنين.'));
  }

  sections.push(snapshot.cashAccountCount > 0
    ? section('DS08_CASH_ACCOUNTS', 'BANK_AND_CASH', 'MANDATORY', 'COMPLETE',
      `${snapshot.cashAccountCount} حسابًا نقديًا بالجنيه. رقم الحساب البنكي يبقى دليلًا خارجيًا.`)
    : section('DS08_CASH_ACCOUNTS', 'BANK_AND_CASH', 'MANDATORY',
      snapshot.projectName ? 'MISSING' : 'BLOCKED',
      'المشروع الحي يحتاج حسابًا نقديًا واحدًا على الأقل.',
      [snapshot.projectName ? 'لا توجد حسابات نقدية.' : 'أنشئ المشروع أولًا.']));

  const statementsApplicable = applicabilityOf(snapshot, 'DS16_BANK_STATEMENTS');
  if (snapshot.cashAccountCount === 0) {
    sections.push(section('DS16_BANK_STATEMENTS', 'BANK_AND_CASH', 'CONDITIONAL', 'BLOCKED',
      'كشوف البنك إلزامية من تاريخ التشغيل الحي.',
      ['أنشئ حسابًا نقديًا أولًا.']));
  } else if (statementsApplicable === false) {
    sections.push(section('DS16_BANK_STATEMENTS', 'BANK_AND_CASH', 'CONDITIONAL', 'NOT_APPLICABLE',
      'كشوف التشغيل الحي لم تبدأ بعد، أو صُرّح بأنها ستُستورد لاحقًا.'));
  } else if (snapshot.bankStatementLineCount > 0) {
    sections.push(section('DS16_BANK_STATEMENTS', 'BANK_AND_CASH', 'CONDITIONAL', 'COMPLETE',
      `${snapshot.bankStatementLineCount} حركة بنكية مستوردة. الاستيراد لا ينشئ قيدًا.`));
  } else {
    sections.push(section('DS16_BANK_STATEMENTS', 'BANK_AND_CASH', 'CONDITIONAL', 'CONDITIONAL_OPEN',
      'من تاريخ التشغيل الحي: لا فجوات في الفترات ولا مراجع مزوّد مكررة.'));
  }

  if (!snapshot.openPeriodExists) {
    sections.push(section('ACCOUNTING_PERIOD', 'BANK_AND_CASH', 'MANDATORY',
      snapshot.projectName ? 'MISSING' : 'BLOCKED',
      'ترحيل الأرصدة الافتتاحية يحتاج فترة محاسبية مفتوحة تغطي تاريخ الترحيل.',
      [snapshot.projectName ? 'لا توجد فترة محاسبية مفتوحة.' : 'أنشئ المشروع أولًا.']));
  } else if (snapshot.freezeDate && !snapshot.openPeriodCoversFreeze) {
    sections.push(section('ACCOUNTING_PERIOD', 'BANK_AND_CASH', 'MANDATORY', 'FAILED',
      'الفترة المفتوحة لا تغطي تاريخ التجميد.',
      ['افتح فترة تغطي تاريخ التجميد قبل اعتماد الاستيراد الافتتاحي.']));
  } else {
    sections.push(section('ACCOUNTING_PERIOD', 'BANK_AND_CASH', 'MANDATORY', 'COMPLETE',
      'توجد فترة محاسبية مفتوحة جاهزة لترحيل القيد الافتتاحي.'));
  }

  if (!snapshot.realEstateProfile || snapshot.assetCount === 0 || snapshot.parcelCount === 0) {
    const reasons: string[] = [];
    if (!snapshot.realEstateProfile) reasons.push('ملف الاستراتيجية العقارية غير مُنشأ.');
    if (snapshot.assetCount === 0) reasons.push('لا توجد أصول عقارية.');
    if (snapshot.parcelCount === 0) reasons.push('لا توجد قطع بمساحة ووحدة.');
    sections.push(section('DS11_PROPERTY', 'PROPERTY', 'MANDATORY',
      snapshot.projectName ? (reasons.length === 3 ? 'MISSING' : 'IN_PROGRESS') : 'BLOCKED',
      'الاستراتيجية والأصل والقطعة والمساحة وحدة لا تُخزَّن كنص حر.',
      snapshot.projectName ? reasons : ['أنشئ المشروع أولًا.']));
  } else {
    sections.push(section('DS11_PROPERTY', 'PROPERTY', 'MANDATORY', 'COMPLETE',
      `${snapshot.assetCount} أصلًا · ${snapshot.parcelCount} قطعة · ${snapshot.realEstateStrategy ?? '—'}.`));
  }

  const acquisitionApplicable = applicabilityOf(snapshot, 'DS12_ACQUISITION');
  if (snapshot.assetCount === 0) {
    sections.push(section('DS12_ACQUISITION', 'PROPERTY', 'CONDITIONAL', 'BLOCKED',
      'الاستحواذ للأصول المملوكة فعلًا في تاريخ التجميد.',
      ['أضف أصلًا عقاريًا أولًا.']));
  } else if (acquisitionApplicable === false) {
    sections.push(section('DS12_ACQUISITION', 'PROPERTY', 'CONDITIONAL', 'NOT_APPLICABLE',
      'لا توجد أصول مستحوذ عليها في تاريخ التجميد.'));
  } else if (snapshot.acquisitionCount >= snapshot.assetCount) {
    sections.push(section('DS12_ACQUISITION', 'PROPERTY', 'CONDITIONAL', 'COMPLETE',
      'سُجّل عقد استحواذ لكل أصل حالي.'));
  } else if (snapshot.acquisitionCount > 0) {
    sections.push(section('DS12_ACQUISITION', 'PROPERTY', 'CONDITIONAL', 'IN_PROGRESS',
      `${snapshot.acquisitionCount} من ${snapshot.assetCount} أصول لها عقد استحواذ.`,
      ['أدخل أساس الاستحواذ لكل أصل مملوك، أو صرّح بأن الأصل غير مستحوذ عليه.']));
  } else {
    sections.push(section('DS12_ACQUISITION', 'PROPERTY', 'CONDITIONAL', 'CONDITIONAL_OPEN',
      'إن كانت الأصول مستحوذًا عليها فأدخل البائع والعقد والمقابل وتكاليف الإقفال والدليل.'));
  }

  const developmentApplicable = applicabilityOf(snapshot, 'DS13_DEVELOPMENT');
  const developSell = snapshot.realEstateStrategy === 'DEVELOP_SELL';
  if (!snapshot.realEstateProfile) {
    sections.push(section('DS13_DEVELOPMENT', 'PROPERTY', 'CONDITIONAL', 'BLOCKED',
      'ميزانية التطوير المعتمدة إلزامية عند وجود نشاط تطوير.',
      ['أنشئ الملف العقاري أولًا.']));
  } else if (developmentApplicable === false) {
    sections.push(section('DS13_DEVELOPMENT', 'PROPERTY', 'CONDITIONAL', 'NOT_APPLICABLE',
      'لا يوجد نشاط تطوير يستدعي ميزانية معتمدة.'));
  } else if (snapshot.approvedBudgetCount > 0) {
    sections.push(section('DS13_DEVELOPMENT', 'PROPERTY', 'CONDITIONAL', 'COMPLETE',
      `${snapshot.approvedBudgetCount} نسخة ميزانية معتمدة. التكلفة حتى التاريخ تدخل كأعمال تحت التنفيذ افتتاحية.`));
  } else if (developSell) {
    sections.push(section('DS13_DEVELOPMENT', 'PROPERTY', 'CONDITIONAL', 'MISSING',
      'استراتيجية التطوير ثم البيع تتطلب ميزانية معتمدة أو تصريحًا بأنها لا تنطبق.',
      ['لا توجد نسخة ميزانية معتمدة.']));
  } else {
    sections.push(section('DS13_DEVELOPMENT', 'PROPERTY', 'CONDITIONAL', 'CONDITIONAL_OPEN',
      'إن وُجد نشاط تطوير فأدخل بنود الميزانية المعتمدة وتصنيف التكلفة صراحة: مصروف أو أعمال قابلة للرسملة.'));
  }

  if (snapshot.declaredDebitTotal !== null && snapshot.declaredCreditTotal !== null) {
    if (snapshot.declaredDebitTotal !== snapshot.declaredCreditTotal) {
      sections.push(section('CONTROL_TOTALS', 'OPENING_POSITION', 'MANDATORY', 'FAILED',
        'المجاميع المعلنة غير متوازنة.',
        ['إجمالي المدين يجب أن يساوي إجمالي الدائن قبل أي تجهيز.']));
    } else {
      sections.push(section('CONTROL_TOTALS', 'OPENING_POSITION', 'MANDATORY', 'COMPLETE',
        `مدين معلن ${snapshot.declaredDebitTotal} = دائن معلن ${snapshot.declaredCreditTotal} وحدة صغرى.`));
    }
  } else {
    sections.push(section('CONTROL_TOTALS', 'OPENING_POSITION', 'MANDATORY',
      snapshot.freezeDate ? 'MISSING' : 'BLOCKED',
      'المجاميع الرقابية الموقعة شرط قبل تجهيز الاستيراد الافتتاحي.',
      [snapshot.freezeDate ? 'المجاميع الرقابية غير مُعلنة.' : 'سجّل تاريخ التجميد أولًا.']));
  }

  const opening = snapshot.openingImportStatus;
  if (!opening) {
    sections.push(section('DS09_OPENING_BALANCES', 'OPENING_POSITION', 'MANDATORY',
      snapshot.declaredDebitTotal && snapshot.cashAccountCount > 0 ? 'MISSING' : 'BLOCKED',
      'الأرصدة الافتتاحية تدخل فقط عبر الاستيراد المضبوط وستة ترميزات معتمدة.',
      snapshot.declaredDebitTotal && snapshot.cashAccountCount > 0
        ? ['لم يُجهَّز استيراد افتتاحي بعد.']
        : ['أكمل المجاميع الرقابية والحساب النقدي أولًا.']));
  } else if (opening === 'REJECTED' || opening === 'FAILED' || snapshot.openingRejectedRowCount > 0) {
    sections.push(section('DS09_OPENING_BALANCES', 'OPENING_POSITION', 'MANDATORY', 'FAILED',
      'الاستيراد يحمل سطورًا مرفوضة أو فشل التحقق.',
      ['لا يُرحَّل أي سطر مرفوض. صحّح المصدر وأعد التجهيز.']));
  } else if (opening === 'POSTED' && snapshot.openingIsReversed) {
    sections.push(section('DS09_OPENING_BALANCES', 'OPENING_POSITION', 'MANDATORY', 'FAILED',
      'الاستيراد المرحّل معكوس. جهّز استيرادًا مصححًا بعد العكس.',
      ['القيد الافتتاحي النشط غير موجود.']));
  } else if (opening === 'DRAFT') {
    sections.push(section('DS09_OPENING_BALANCES', 'OPENING_POSITION', 'MANDATORY', 'IN_PROGRESS',
      'مسودة استيراد جاهزة للتحقق.'));
  } else {
    sections.push(section('DS09_OPENING_BALANCES', 'OPENING_POSITION', 'MANDATORY', 'COMPLETE',
      `الاستيراد في حالة ${opening}. الترميزات المستخدمة: ${snapshot.openingMappingCodes.join(', ') || '—'}.`));
  }

  const supplierApplicable = applicabilityOf(snapshot, 'DS10_UNPAID_SUPPLIERS');
  const hasSupplier = snapshot.openingMappingCodes.includes('OPENING_SUPPLIER_PAYABLE');
  if (supplierApplicable === false) {
    sections.push(section('DS10_UNPAID_SUPPLIERS', 'OPENING_POSITION', 'CONDITIONAL', 'NOT_APPLICABLE',
      'لا توجد التزامات موردين غير مسددة في تاريخ التجميد.'));
  } else if (hasSupplier) {
    sections.push(section('DS10_UNPAID_SUPPLIERS', 'OPENING_POSITION', 'CONDITIONAL', 'COMPLETE',
      'عُبّر عن الالتزام عبر ترميز مستحق الموردين الافتتاحي.'));
  } else {
    sections.push(section('DS10_UNPAID_SUPPLIERS', 'OPENING_POSITION', 'CONDITIONAL',
      opening ? 'CONDITIONAL_OPEN' : 'BLOCKED',
      'إن وُجدت فواتير غير مسددة فأدخلها كمستحق موردين افتتاحي مع الطرف والمبلغ والدليل.',
      opening ? [] : ['جهّز الاستيراد الافتتاحي أولًا أو صرّح بأنها لا تنطبق.']));
  }

  const salesApplicable = applicabilityOf(snapshot, 'DS14_SALES');
  const hasReceivable = snapshot.openingMappingCodes.includes('OPENING_CUSTOMER_RECEIVABLE');
  if (salesApplicable === false) {
    sections.push(section('DS14_SALES', 'OPENING_POSITION', 'CONDITIONAL', 'NOT_APPLICABLE',
      'لا تُعاد إثبات مبيعات مكتملة قبل التجميد.'));
  } else if (hasReceivable) {
    sections.push(section('DS14_SALES', 'OPENING_POSITION', 'CONDITIONAL', 'COMPLETE',
      'الذمم المتبقية دخلت كمستحق عملاء افتتاحي. المبيعات المكتملة لا تُعاد.'));
  } else {
    sections.push(section('DS14_SALES', 'OPENING_POSITION', 'CONDITIONAL',
      opening ? 'CONDITIONAL_OPEN' : 'BLOCKED',
      'المبيعات المكتملة قبل التجميد لا تُعاد. المتبقي فقط: نقد أو ذمم افتتاحية.',
      opening ? [] : ['جهّز الاستيراد الافتتاحي أو صرّح بأنها لا تنطبق.']));
  }

  const distApplicable = applicabilityOf(snapshot, 'DS15_DISTRIBUTIONS');
  const hasDist = snapshot.openingMappingCodes.includes('OPENING_DISTRIBUTION_PAYABLE');
  if (distApplicable === false) {
    sections.push(section('DS15_DISTRIBUTIONS', 'OPENING_POSITION', 'CONDITIONAL', 'NOT_APPLICABLE',
      'لا توجد توزيعات معتمدة غير مدفوعة في تاريخ التجميد.'));
  } else if (hasDist) {
    sections.push(section('DS15_DISTRIBUTIONS', 'OPENING_POSITION', 'CONDITIONAL', 'COMPLETE',
      'التوزيعات المعتمدة غير المدفوعة دخلت كمستحق توزيع افتتاحي.'));
  } else {
    sections.push(section('DS15_DISTRIBUTIONS', 'OPENING_POSITION', 'CONDITIONAL',
      opening ? 'CONDITIONAL_OPEN' : 'BLOCKED',
      'المدفوع تاريخيًا يبقى دليلًا ويظهر في النقدية ورأس المال فقط.',
      opening ? [] : ['جهّز الاستيراد الافتتاحي أو صرّح بأنها لا تنطبق.']));
  }

  const validated = opening !== null
    && ['VALIDATED', 'READY_FOR_APPROVAL', 'APPROVED', 'POSTED'].includes(opening)
    && snapshot.openingRejectedRowCount === 0
    && snapshot.openingControlTotalsMatch === true
    && zero(snapshot.openingDebitVariance)
    && zero(snapshot.openingCreditVariance);
  if (!opening) {
    sections.push(section('OPENING_VALIDATION', 'VALIDATION_AND_RECONCILIATION', 'DERIVED', 'BLOCKED',
      'التحقق يعيد حساب المجاميع داخل قاعدة البيانات.',
      ['لا يوجد استيراد للتحقق منه.']));
  } else if (validated) {
    sections.push(section('OPENING_VALIDATION', 'VALIDATION_AND_RECONCILIATION', 'DERIVED', 'COMPLETE',
      'صفر سطور مرفوضة · المدين المعلن = المحسوب · الدائن المعلن = المحسوب · المدين = الدائن.'));
  } else if (opening === 'DRAFT') {
    sections.push(section('OPENING_VALIDATION', 'VALIDATION_AND_RECONCILIATION', 'DERIVED', 'IN_PROGRESS',
      'شغّل التحقق لإعادة حساب المجاميع.'));
  } else {
    sections.push(section('OPENING_VALIDATION', 'VALIDATION_AND_RECONCILIATION', 'DERIVED', 'FAILED',
      'التحقق لم يمر بفرق صفري.',
      ['أي فرق غير صفري أو سطر مرفوض يمنع الاعتماد.']));
  }

  const approved = opening === 'APPROVED' || opening === 'POSTED';
  if (!validated) {
    sections.push(section('OPENING_APPROVAL', 'VALIDATION_AND_RECONCILIATION', 'DERIVED', 'BLOCKED',
      'المعتمد شخص مختلف عن مُعدّ الملف.',
      ['لا يُعرض الاعتماد قبل نجاح التحقق.']));
  } else if (approved) {
    sections.push(section('OPENING_APPROVAL', 'VALIDATION_AND_RECONCILIATION', 'DERIVED', 'COMPLETE',
      'اعتمد مالك مختلف عن المعدّ الاستيراد.'));
  } else {
    sections.push(section('OPENING_APPROVAL', 'VALIDATION_AND_RECONCILIATION', 'DERIVED', 'IN_PROGRESS',
      opening === 'READY_FOR_APPROVAL'
        ? 'بانتظار اعتماد مالك مختلف عن المعدّ.'
        : 'رشّح الاستيراد للاعتماد بعد مراجعة المجاميع.'));
  }

  if (opening === 'POSTED' && !snapshot.openingIsReversed) {
    sections.push(section('OPENING_POSTING', 'VALIDATION_AND_RECONCILIATION', 'DERIVED', 'COMPLETE',
      'القيد الافتتاحي مُرحَّل عبر الأمر المعتمد. لا تعديل مباشر بعد الترحيل.'));
  } else if (opening === 'POSTED' && snapshot.openingIsReversed) {
    sections.push(section('OPENING_POSTING', 'VALIDATION_AND_RECONCILIATION', 'DERIVED', 'FAILED',
      'القيد الافتتاحي معكوس.',
      ['التصحيح يتم بعكس مرتبط ثم استيراد جديد.']));
  } else {
    sections.push(section('OPENING_POSTING', 'VALIDATION_AND_RECONCILIATION', 'DERIVED',
      approved ? 'IN_PROGRESS' : 'BLOCKED',
      'الترحيل ذري عبر سجل الحسابات الدلالية القائم.',
      approved ? [] : ['لا ترحيل قبل الاعتماد.']));
  }

  if (opening !== 'POSTED' || snapshot.openingIsReversed) {
    sections.push(section('OPENING_RECONCILIATION', 'VALIDATION_AND_RECONCILIATION', 'DERIVED', 'BLOCKED',
      'المطابقة تقارن القيود المرحّلة بالمجاميع الخارجية الموقعة.',
      ['لا مطابقة قبل ترحيل استيراد نشط.']));
  } else if (snapshot.openCriticalExceptions > 0 || snapshot.nonZeroVarianceCheckpoints > 0) {
    sections.push(section('OPENING_RECONCILIATION', 'VALIDATION_AND_RECONCILIATION', 'DERIVED', 'FAILED',
      'توجد فروق غير صفرية أو استثناءات حرجة مفتوحة.',
      ['القبول = فرق 0 وحدة صغرى لكل نقطة. أي شيء آخر فشل.']));
  } else if (snapshot.matchedZeroVarianceCheckpoints === 0) {
    sections.push(section('OPENING_RECONCILIATION', 'VALIDATION_AND_RECONCILIATION', 'DERIVED', 'IN_PROGRESS',
      'سجّل نقاط المطابقة بعد الترحيل. الصفر يُعلن صراحة.'));
  } else {
    sections.push(section('OPENING_RECONCILIATION', 'VALIDATION_AND_RECONCILIATION', 'DERIVED', 'COMPLETE',
      `${snapshot.matchedZeroVarianceCheckpoints} نقطة مطابقة بفرق صفري.`));
  }

  const materialEvidence = snapshot.evidenceItemCount > 0
    || Boolean(snapshot.freezeEvidenceReference)
    || Boolean(snapshot.organizationEvidenceReference)
    || Boolean(snapshot.projectEvidenceReference);
  sections.push(materialEvidence
    ? section('DS17_EVIDENCE', 'VALIDATION_AND_RECONCILIATION', 'MANDATORY', 'COMPLETE',
      `${snapshot.evidenceItemCount} مرجعًا في السجل. المستندات تبقى في أنظمة العميل.`)
    : section('DS17_EVIDENCE', 'VALIDATION_AND_RECONCILIATION', 'MANDATORY',
      snapshot.projectName ? 'MISSING' : 'BLOCKED',
      'كل حقيقة مادية تحتاج معرّف دليل وموقع حفظ لدى العميل.',
      [snapshot.projectName ? 'سجل الأدلة فارغ.' : 'أنشئ المشروع أولًا.']));

  return sections;
}

function verdictFor(
  sections: IntakeSection[],
  snapshot: IntakeSnapshot,
): { verdict: ReadinessVerdict; verdictAr: string } {
  const byCode = new Map(sections.map((item) => [item.code, item]));
  const mandatoryMissing = sections.filter((item) =>
    item.kind === 'MANDATORY' && (item.status === 'MISSING' || item.status === 'BLOCKED' || item.status === 'IN_PROGRESS'));
  const failures = sections.filter((item) => item.status === 'FAILED');
  const posted = byCode.get('OPENING_POSTING')?.status === 'COMPLETE';
  const reconciled = byCode.get('OPENING_RECONCILIATION')?.status === 'COMPLETE';
  const openingReady = byCode.get('CONTROL_TOTALS')?.status === 'COMPLETE'
    && byCode.get('DS08_CASH_ACCOUNTS')?.status === 'COMPLETE'
    && byCode.get('FREEZE_DATE')?.status === 'COMPLETE'
    && byCode.get('ACCOUNTING_PERIOD')?.status === 'COMPLETE'
    && snapshot.openModellingGapCount === 0
    && !failures.some((item) => item.code === 'DS09_OPENING_BALANCES');

  if (failures.length > 0 && (posted || byCode.get('DS09_OPENING_BALANCES')?.status === 'FAILED')) {
    return {
      verdict: 'OPENING_BLOCKED',
      verdictAr: 'المركز الافتتاحي متوقف: أصلح أسباب الفشل قبل أي اعتماد أو ترحيل.',
    };
  }
  if (posted && reconciled) {
    return {
      verdict: 'OPENING_RECONCILED_PENDING_REAL_EVIDENCE',
      verdictAr: 'المطابقة التقنية صفرية. المرحلة 2 لا تُغلق إلا ببيانات عميل حقيقية ومجاميع موقعة.',
    };
  }
  if (posted) {
    return {
      verdict: 'OPENING_POSTED_AWAITING_RECONCILIATION',
      verdictAr: 'القيد الافتتاحي مُرحَّل. أكمل نقاط المطابقة بفرق صفري معلن.',
    };
  }
  if (byCode.get('DS09_OPENING_BALANCES')?.status === 'IN_PROGRESS'
    || byCode.get('OPENING_VALIDATION')?.status === 'IN_PROGRESS'
    || byCode.get('OPENING_APPROVAL')?.status === 'IN_PROGRESS') {
    return {
      verdict: 'OPENING_IN_PROGRESS',
      verdictAr: 'الاستيراد الافتتاحي جارٍ عبر المسار المعتمد: مسودة → تحقق → اعتماد → ترحيل.',
    };
  }
  if (openingReady && byCode.get('DS09_OPENING_BALANCES')?.status === 'MISSING') {
    return {
      verdict: 'OPENING_READY_TO_STAGE',
      verdictAr: 'البيانات الأساسية والمجاميع جاهزة لتجهيز الاستيراد الافتتاحي.',
    };
  }
  if (mandatoryMissing.length > 0 || snapshot.openModellingGapCount > 0) {
    return {
      verdict: 'INTAKE_IN_PROGRESS',
      verdictAr: 'أكمل الأقسام الإلزامية الناقصة قبل تجهيز المركز الافتتاحي.',
    };
  }
  return {
    verdict: 'READY_TO_RECEIVE_REAL_DATA',
    verdictAr: 'مسار الإدخال جاهز لاستقبال بيانات المشروع الحقيقي. هذا لا يعني اجتياز المرحلة 2.',
  };
}

export function evaluateIntakeReadiness(snapshot: IntakeSnapshot): IntakeReadiness {
  const evaluated = evaluate(snapshot);
  const resultStatus: SectionStatus = evaluated.some((item) => item.status === 'FAILED')
    ? 'FAILED'
    : evaluated.some((item) => item.kind === 'MANDATORY' && item.status !== 'COMPLETE')
      ? 'IN_PROGRESS'
      : 'COMPLETE';
  const { verdict, verdictAr } = verdictFor(evaluated, snapshot);
  const result = section(
    'READINESS_RESULT',
    'VALIDATION_AND_RECONCILIATION',
    'DERIVED',
    resultStatus,
    verdictAr,
    snapshot.openModellingGapCount > 0
      ? [`${snapshot.openModellingGapCount} فجوة نمذجة مفتوحة: لا تُجبر على ترميز غير مطابق.`]
      : [],
    ['المرحلة 2 لا تُعلَن مكتملة من هذا المسار.'],
  );
  const sections = [...evaluated, result];

  const groups = INTAKE_GROUPS.map((id) => {
    const members = sections.filter((item) => item.group === id && item.code !== 'READINESS_RESULT');
    const countable = members.filter((item) => item.status !== 'NOT_APPLICABLE' && item.status !== 'BLOCKED');
    const complete = countable.filter((item) => item.status === 'COMPLETE').length;
    return {
      id,
      titleAr: GROUP_TITLE[id],
      complete,
      total: Math.max(countable.length, 1),
      hasFailure: members.some((item) => item.status === 'FAILED'),
      next: false,
    };
  });

  const nextSection = sections.find((item) =>
    item.code !== 'READINESS_RESULT'
    && (item.status === 'MISSING' || item.status === 'IN_PROGRESS' || item.status === 'FAILED'
      || (item.status === 'CONDITIONAL_OPEN' && item.kind === 'CONDITIONAL')))?.code ?? null;

  const nextGroup = sections.find((item) => item.code === nextSection)?.group;
  return {
    sections,
    groups: groups.map((group) => ({ ...group, next: group.id === nextGroup })),
    nextSection,
    mandatoryMissing: sections
      .filter((item) => item.kind === 'MANDATORY' && (item.status === 'MISSING' || item.status === 'IN_PROGRESS'))
      .map((item) => item.code),
    failures: sections.filter((item) => item.status === 'FAILED').map((item) => item.code),
    openModellingGaps: snapshot.openModellingGapCount,
    verdict,
    verdictAr,
    phase2Passed: false,
    phase2ReasonAr: 'المرحلة 2 لا تُغلق إلا بعد بيانات عميل حقيقية، وتجميد مصدر موقّع، واستيراد مضبوط، واعتماد/ترحيل، ومطابقة بفرق صفري تام.',
  };
}

export function emptyIntakeSnapshot(): IntakeSnapshot {
  return {
    organizationName: null,
    projectName: null,
    reportingCurrency: null,
    freezeDate: null,
    freezeEvidenceReference: null,
    organizationEvidenceReference: null,
    projectEvidenceReference: null,
    agreementTitleOrReference: null,
    declaredDebitTotal: null,
    declaredCreditTotal: null,
    investorCount: 0,
    activeAgreement: false,
    agreementEffectiveDate: null,
    commitmentCount: 0,
    allocationRulesConfigured: false,
    issuedCallCount: 0,
    contributionCount: 0,
    contributionCashAttributedCount: 0,
    cashAccountCount: 0,
    bankStatementLineCount: 0,
    openPeriodCoversFreeze: false,
    openPeriodExists: false,
    realEstateProfile: false,
    realEstateStrategy: null,
    assetCount: 0,
    parcelCount: 0,
    acquisitionCount: 0,
    approvedBudgetCount: 0,
    openingImportStatus: null,
    openingRejectedRowCount: 0,
    openingControlTotalsMatch: null,
    openingIsReversed: false,
    openingMappingCodes: [],
    openingDebitVariance: null,
    openingCreditVariance: null,
    matchedZeroVarianceCheckpoints: 0,
    nonZeroVarianceCheckpoints: 0,
    openCriticalExceptions: 0,
    evidenceItemCount: 0,
    openModellingGapCount: 0,
    applicability: {},
  };
}

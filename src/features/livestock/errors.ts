const FALLBACK_ERROR = 'تعذر حفظ بيانات الثروة الحيوانية. راجع البيانات والصلاحيات وحاول مجددًا.';

type ErrorRule = Readonly<{
  includes: string;
  message: string;
}>;

const ERROR_RULES: readonly ErrorRule[] = [
  { includes: 'idempotency key payload mismatch', message: 'مفتاح العملية استُخدم لبيانات مختلفة. حدّث الصفحة وأعد المحاولة.' },
  { includes: 'forbidden', message: 'لا تملك صلاحية تنفيذ هذا الإجراء.' },
  { includes: 'livestock project not found', message: 'مشروع الثروة الحيوانية غير موجود أو لا ينتمي إلى هذه المنظمة.' },
  { includes: 'livestock site not found', message: 'موقع التشغيل غير موجود في هذا المشروع.' },
  { includes: 'livestock herd not found', message: 'القطيع غير موجود في هذا المشروع.' },
  { includes: 'livestock cohort not found', message: 'الدفعة الحيوانية غير موجودة في هذا المشروع.' },
  { includes: 'invalid livestock species', message: 'نوع الحيوان غير صالح.' },
  { includes: 'invalid livestock purpose', message: 'غرض القطيع غير صالح.' },
  { includes: 'invalid livestock cohort origin', message: 'مصدر الدفعة غير صالح.' },
  { includes: 'invalid livestock opening headcount', message: 'العدد عند بداية الدفعة يجب أن يكون عددًا صحيحًا أكبر من صفر.' },
  { includes: 'invalid livestock opening weight', message: 'بيانات الوزن الافتتاحي غير صالحة أو غير مكتملة.' },
  { includes: 'livestock site reference already exists', message: 'مرجع موقع التشغيل مستخدم بالفعل في هذا المشروع.' },
  { includes: 'livestock herd reference already exists', message: 'مرجع القطيع مستخدم بالفعل في هذا المشروع.' },
  { includes: 'livestock cohort reference already exists', message: 'مرجع الدفعة مستخدم بالفعل في هذا المشروع.' },
  { includes: 'expected livestock cohort state mismatch', message: 'تغيّرت حالة الدفعة. حدّث الصفحة قبل إعادة المحاولة.' },
  { includes: 'invalid livestock cohort transition', message: 'انتقال حالة الدفعة غير مسموح.' },
  { includes: 'authentication required', message: 'انتهت جلسة الدخول. سجّل الدخول ثم أعد المحاولة.' },
];

export function livestockErrorMessage(databaseMessage?: string): string {
  const match = ERROR_RULES.find((rule) => databaseMessage?.includes(rule.includes));
  return match?.message ?? FALLBACK_ERROR;
}

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
  // GF-021 — movement, derived placement, and weight events.
  { includes: 'livestock cohort is not active', message: 'الدفعة غير نشطة. فعّل الدفعة قبل تسجيل أحداث تشغيلية عليها.' },
  { includes: 'source is not the current placement', message: 'تغيّر الموقع الحالي للدفعة منذ فتح الشاشة. حدّث الصفحة لقراءة الموقع الحالي ثم أعد المحاولة.' },
  { includes: 'must change site or herd', message: 'لا تُسجَّل حركة بدون تغيير: يجب أن يختلف الموقع أو القطيع الوجهة.' },
  { includes: 'invalid livestock movement reason', message: 'سبب النقل مطلوب (٣ أحرف على الأقل).' },
  { includes: 'invalid livestock movement effective time', message: 'تاريخ ووقت النقل مطلوب.' },
  { includes: 'movement effective time precedes its predecessor', message: 'لا يمكن تسجيل حركة بتاريخ أسبق من الحركة السابقة لها.' },
  { includes: 'invalid livestock placement chain tip count', message: 'سلسلة مواقع الدفعة غير متسقة. تواصل مع الدعم؛ لن يعرض النظام موقعًا حاليًا غير مؤكد.' },
  { includes: 'opening placement not found', message: 'لا يوجد وضع افتتاحي مسجل لهذه الدفعة.' },
  { includes: 'requires a sample size', message: 'الوزن بالعينة يتطلب حجم العينة.' },
  { includes: 'requires an evidence reference', message: 'الوزن بالعينة يتطلب مرجع دليل.' },
  { includes: 'requires a measured animal count', message: 'القياس الفردي يتطلب عدد الحيوانات التي شملها الوزن.' },
  { includes: 'sample size exceeds current derived quantity', message: 'حجم العينة أكبر من العدد الحالي المشتق للدفعة.' },
  { includes: 'measured animal count exceeds current derived quantity', message: 'عدد الحيوانات المقاسة أكبر من العدد الحالي المشتق للدفعة.' },
  { includes: 'does not take a sample size', message: 'هذا الأسلوب لا يقبل حجم عينة.' },
  { includes: 'does not take a measured animal count', message: 'هذا الأسلوب لا يقبل عدد حيوانات مقاسة.' },
  { includes: 'does not take population metadata', message: 'هذا الأسلوب لا يقبل بيانات عينة أو عدد حيوانات مقاسة.' },
  { includes: 'invalid livestock weight method', message: 'أسلوب قياس الوزن غير صالح.' },
  { includes: 'invalid livestock weight value', message: 'قيمة الوزن يجب أن تكون أكبر من صفر.' },
  { includes: 'invalid livestock weight unit', message: 'وحدة الوزن يجب أن تكون الكيلوجرام.' },
  { includes: 'invalid livestock weight effective time', message: 'تاريخ ووقت القياس مطلوب.' },
  { includes: 'invalid negative livestock derived quantity', message: 'الرصيد العددي المشتق غير صالح. تواصل مع الدعم.' },
  // GF-022 — births, mortality, split and merge.
  { includes: 'exceeds the current derived quantity', message: 'العدد المطلوب أكبر من الرصيد العددي الحالي المشتق للدفعة. حدّث الصفحة لقراءة الرصيد الحالي ثم أعد المحاولة.' },
  { includes: 'cannot go below zero', message: 'لا يمكن أن ينخفض الرصيد العددي عن صفر.' },
  { includes: 'invalid livestock quantity', message: 'العدد يجب أن يكون عددًا صحيحًا أكبر من صفر.' },
  { includes: 'invalid livestock mortality cause', message: 'سبب النفوق غير صالح.' },
  { includes: 'invalid livestock event effective time', message: 'تاريخ ووقت الواقعة مطلوب.' },
  { includes: 'invalid livestock operation reason', message: 'سبب العملية مطلوب (٣ أحرف على الأقل).' },
  { includes: 'at least two source cohorts', message: 'الدمج يتطلب دفعتين مصدر على الأقل.' },
  { includes: 'must match the source cohorts', message: 'عدد الكميات يجب أن يطابق عدد الدفعات المصدر.' },
  { includes: 'must be distinct', message: 'لا يمكن دمج الدفعة مع نفسها؛ اختر دفعات مختلفة.' },
  { includes: 'compatible species', message: 'لا يمكن دمج دفعات من أنواع حيوانية مختلفة.' },
  { includes: 'does not conserve quantity', message: 'العملية لا تحافظ على العدد. لم يُحفظ أي تغيير.' },
  { includes: 'requires both an outgoing and an incoming leg', message: 'العملية غير مكتملة الطرفين. لم يُحفظ أي تغيير.' },
  { includes: 'requires an operation identity', message: 'حركة التقسيم أو الدمج يجب أن ترتبط بعملية واحدة.' },
  { includes: 'requires a cause category', message: 'تصنيف السبب مطلوب لهذه الواقعة.' },
];

export function livestockErrorMessage(databaseMessage?: string): string {
  const match = ERROR_RULES.find((rule) => databaseMessage?.includes(rule.includes));
  return match?.message ?? FALLBACK_ERROR;
}

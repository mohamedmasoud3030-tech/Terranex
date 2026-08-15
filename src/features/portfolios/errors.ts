/**
 * Operator-safe Arabic mapping for R1 portfolio command errors.
 * PostgREST/Supabase internals are never shown to the operator.
 */

const FALLBACK_ERROR = 'تعذر حفظ بيانات المحفظة. راجع البيانات والصلاحيات وحاول مجددًا.';

type ErrorRule = Readonly<{
  includes: string;
  message: string;
}>;

const ERROR_RULES: readonly ErrorRule[] = [
  { includes: 'idempotency key payload mismatch', message: 'مفتاح العملية استُخدم لبيانات مختلفة. حدّث الصفحة وأعد المحاولة.' },
  { includes: 'forbidden', message: 'لا تملك صلاحية تنفيذ هذا الإجراء.' },
  { includes: 'authentication required', message: 'انتهت جلسة الدخول. سجّل الدخول ثم أعد المحاولة.' },
  { includes: 'invalid portfolio name', message: 'اسم المحفظة مطلوب (حرفان على الأقل وحتى 120 حرفًا).' },
  { includes: 'invalid portfolio description', message: 'وصف المحفظة طويل جدًا أو أقصر من الحد المسموح.' },
  { includes: 'invalid idempotency key', message: 'مفتاح العملية غير صالح. حدّث الصفحة وأعد المحاولة.' },
  { includes: 'portfolio not found', message: 'المحفظة غير موجودة أو لا تنتمي إلى هذه المنظمة.' },
  { includes: 'archived portfolio metadata is read-only', message: 'المحفظة مؤرشفة؛ بياناتها الإدارية للقراءة فقط.' },
  { includes: 'responsible manager must be an active member', message: 'المدير المسؤول يجب أن يكون عضوًا نشطًا في نفس المنظمة.' },
  { includes: 'invalid portfolio transition reason', message: 'سبب تغيير الحالة مطلوب (٣ أحرف على الأقل).' },
  { includes: 'invalid new portfolio status', message: 'الحالة المطلوبة غير صالحة.' },
  { includes: 'expected portfolio status mismatch', message: 'تغيّرت حالة المحفظة منذ فتح الشاشة. حدّث الصفحة ثم أعد المحاولة.' },
  { includes: 'invalid portfolio transition', message: 'تغيير حالة المحفظة غير مسموح بالترتيب المطلوب.' },
  { includes: 'projects can only be assigned to an active portfolio', message: 'لا يمكن إسناد المشاريع إلا إلى محفظة نشطة. فعّل المحفظة أولًا.' },
  { includes: 'projects can only be moved to an active portfolio', message: 'لا يمكن نقل المشاريع إلا إلى محفظة نشطة. فعّل محفظة الوجهة أولًا.' },
  { includes: 'project not found in portfolio organization', message: 'المشروع غير موجود في نفس المنظمة.' },
  { includes: 'project already assigned to a portfolio', message: 'المشروع مُسند بالفعل إلى محفظة. استخدم النقل لتغيير محفظته.' },
  { includes: 'invalid portfolio membership removal reason', message: 'سبب الإزالة مطلوب (٣ أحرف على الأقل).' },
  { includes: 'invalid portfolio membership move reason', message: 'سبب النقل مطلوب (٣ أحرف على الأقل).' },
  { includes: 'portfolio membership not found', message: 'لا يوجد إسناد قائم بين هذا المشروع وهذه المحفظة.' },
  { includes: 'project is not assigned to a portfolio; assign it instead', message: 'المشروع غير مُسند إلى أي محفظة؛ استخدم الإسناد بدلًا من النقل.' },
  { includes: 'project is already in the target portfolio', message: 'المشروع موجود بالفعل في محفظة الوجهة.' },
  { includes: 'portfolio membership removal is final', message: 'إزالة الإسناد نهائية ولا يمكن تعديلها.' },
  { includes: 'portfolio membership facts are immutable', message: 'حقول الإسناد غير قابلة للتعديل.' },
  { includes: 'portfolio membership history is append-only', message: 'سجل الإسنادات نهائي ولا يسمح بالحذف.' },
  { includes: 'portfolio status history is append-only', message: 'سجل حالات المحفظة نهائي ولا يسمح بالتعديل.' },
];

export function portfolioErrorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  const rule = ERROR_RULES.find((candidate) => message.includes(candidate.includes));
  return rule ? rule.message : FALLBACK_ERROR;
}

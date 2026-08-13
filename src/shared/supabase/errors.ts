/** Neutralize PostgREST/Supabase internals for operator-facing pages. */
export function operatorQueryError(error: unknown): Error {
  const code = typeof error === 'object' && error && 'code' in error
    ? String((error as { code?: string }).code)
    : '';
  if (code === 'PGRST116' || code === '42501' || /permission|rls|jwt/i.test(String(error))) {
    return new Error('تعذر قراءة بيانات هذا المشروع. تحقق من صلاحية العضوية ثم أعد المحاولة.');
  }
  return new Error('تعذر تحميل بيانات المشروع الآن. أعد المحاولة بعد لحظات.');
}

export function throwOperatorQuery(error: unknown): never {
  throw operatorQueryError(error);
}

/**
 * Server error translator — converts English RPC / PostgREST error messages
 * into Arabic so the UI never shows raw server text to an Arabic-first user.
 *
 * Messages that already contain Arabic characters (the storage layer throws
 * Arabic errors) pass through unchanged.
 */

const SERVER_ERROR_TRANSLATIONS: Record<string, string> = {
  'stock adjustment cannot produce negative quantity or value': 'لا يمكن أن ينتج عن التسوية كمية أو قيمة سالبة.',
  'transaction not found': 'المعاملة غير موجودة.',
  'only active settlements can be reversed': 'لا يمكن عكس إلا التسويات النشطة.',
  'document not found': 'المستند غير موجود.',
  'obligation not found': 'الالتزام غير موجود.',
};

const ARABIC_CHARS = /[\u0600-\u06FF]/;

const GENERIC_ERROR_AR = 'حدث خطأ غير متوقع، يرجى المحاولة مرة أخرى.';

function extractErrorMessage(error: unknown): string {
  if (typeof error === 'string') return error;
  if (error instanceof Error) return error.message;
  if (error && typeof error === 'object' && 'message' in error) {
    const message = (error as { message: unknown }).message;
    return typeof message === 'string' ? message : String(message);
  }
  return String(error ?? '');
}

export function translateServerError(error: unknown): string {
  const message = extractErrorMessage(error).trim();
  if (!message) return GENERIC_ERROR_AR;

  // Already Arabic (storage-layer messages) — keep the specific message.
  if (ARABIC_CHARS.test(message)) return message;

  const normalized = message.toLowerCase();
  for (const [english, arabic] of Object.entries(SERVER_ERROR_TRANSLATIONS)) {
    if (normalized.includes(english)) return arabic;
  }
  return GENERIC_ERROR_AR;
}

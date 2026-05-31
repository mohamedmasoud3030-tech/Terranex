export type StorageOperation = 'read' | 'write' | 'remove' | 'migration';

const AR_MESSAGES: Record<StorageOperation, string> = {
  read: 'تعذر قراءة البيانات المحلية. قد تكون البيانات تالفة أو غير متاحة.',
  write: 'تعذر حفظ البيانات محلياً. تحقق من مساحة التخزين أو إعدادات المتصفح.',
  remove: 'تعذر حذف البيانات المحلية. حاول مرة أخرى.',
  migration: 'تعذر ترقية البيانات المحلية. تم حفظ السجلات غير القابلة للترقية كنسخة احتياطية عند الإمكان.',
};

export class LocalStorageError extends Error {
  readonly key: string;
  readonly operation: StorageOperation;
  readonly arabicMessage: string;
  readonly cause?: unknown;

  constructor(operation: StorageOperation, key: string, cause?: unknown) {
    super(`${operation} failed for localStorage key ${key}`);
    this.name = 'LocalStorageError';
    this.key = key;
    this.operation = operation;
    this.arabicMessage = AR_MESSAGES[operation];
    this.cause = cause;
  }
}

export function getStorageErrorMessage(error: unknown) {
  if (error instanceof LocalStorageError) return error.arabicMessage;
  return 'حدث خطأ غير متوقع أثناء التعامل مع البيانات المحلية.';
}

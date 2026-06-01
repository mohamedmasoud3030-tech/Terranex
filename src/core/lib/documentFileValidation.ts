export const MAX_DOCUMENT_FILE_SIZE_BYTES = 10 * 1024 * 1024;

interface UploadCandidate {
  name: string;
  type: string;
  size: number;
}

const ALLOWED_FILE_TYPES = new Map<string, readonly string[]>([
  ['.pdf', ['application/pdf']],
  ['.jpg', ['image/jpeg']],
  ['.jpeg', ['image/jpeg']],
  ['.png', ['image/png']],
  ['.doc', ['application/msword']],
  ['.docx', ['application/vnd.openxmlformats-officedocument.wordprocessingml.document']],
  ['.xls', ['application/vnd.ms-excel']],
  ['.xlsx', ['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']],
]);

function readExtension(fileName: string) {
  const normalized = fileName.trim().toLowerCase();
  const dotIndex = normalized.lastIndexOf('.');
  return dotIndex >= 0 ? normalized.slice(dotIndex) : '';
}

export function validateDocumentUpload(file: UploadCandidate) {
  if (!file.name.trim()) throw new Error('اسم الملف مطلوب.');
  if (!Number.isFinite(file.size) || file.size <= 0) throw new Error('الملف فارغ أو حجمه غير صالح.');
  if (file.size > MAX_DOCUMENT_FILE_SIZE_BYTES) throw new Error('حجم الملف يتجاوز الحد الأقصى المسموح به وهو 10 ميجابايت.');

  const extension = readExtension(file.name);
  const allowedMimeTypes = ALLOWED_FILE_TYPES.get(extension);
  if (!allowedMimeTypes) throw new Error('نوع الملف غير مدعوم. استخدم PDF أو JPG أو PNG أو Word أو Excel.');
  if (!allowedMimeTypes.includes(file.type)) throw new Error('نوع الملف الفعلي لا يطابق امتداد الملف.');

  return { extension, mime_type: file.type, size_bytes: file.size };
}

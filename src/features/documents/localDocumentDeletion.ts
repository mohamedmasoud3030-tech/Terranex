import { deleteDocumentFile, getDocumentFile, restoreDocumentFile } from '../../core/storage/indexedDbFileStore';
import { documentsStore } from './storage';
import type { Document } from '../../core/types/domain';

export async function deleteLocalDocumentSafely(document: Document) {
  if (!document.file_url) {
    documentsStore.remove(document.id);
    return;
  }

  const storedFile = await getDocumentFile(document.file_url);
  if (!storedFile) throw new Error('الملف المحلي غير موجود على هذا الجهاز. لم يتم حذف سجل المستند.');

  await deleteDocumentFile(document.file_url);
  try {
    documentsStore.remove(document.id);
  } catch (error) {
    try {
      await restoreDocumentFile(storedFile);
    } catch {
      throw new Error('تعذر حذف سجل المستند وتعذر استعادة الملف المحلي بعد محاولة الحذف.');
    }
    throw error;
  }
}

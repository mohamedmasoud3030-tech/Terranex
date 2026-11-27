'use server';

import { createHash } from 'node:crypto';
import { revalidatePath } from 'next/cache';
import type { ActionState } from '@/features/auth/actions';
import { commandFailureState, commandSuccessState } from '@/shared/idempotency';
import { createClient } from '@/shared/supabase/server';
import { generalDocumentSchema } from './schema';

function fail(prev: ActionState, error: string): ActionState {
  return commandFailureState(prev, error);
}

function domainError(prev: ActionState, message: string | undefined, fallback: string): ActionState {
  const text = message ?? '';
  if (text.includes('idempotency key payload mismatch')) return fail(prev, 'مفتاح العملية استُخدم لبيانات مختلفة. حدّث الصفحة وأعد المحاولة.');
  if (text.includes('authentication required')) return fail(prev, 'انتهت جلسة الدخول. سجّل الدخول ثم أعد المحاولة.');
  if (text.includes('forbidden')) return fail(prev, 'لا تملك صلاحية تنفيذ هذا الإجراء على هذه المنظمة.');
  if (text.includes('project not found')) return fail(prev, 'المشروع غير موجود في هذه المنظمة.');
  if (text.includes('document not found')) return fail(prev, 'المستند غير موجود في هذه المنظمة.');
  if (text.includes('immutable across versions')) return fail(prev, 'نسخة المستند الجديدة يجب أن تتبع نفس المستند والعنوان والتصنيف.');
  if (text.includes('document storage object not found')) return fail(prev, 'لم يثبت اكتمال رفع الملف الخاص. أعد رفع الملف ثم حاول مجددًا.');
  if (text.includes('does not match storage object') || text.includes('invalid size metadata')) return fail(prev, 'بيانات الملف لا تطابق النسخة المحفوظة في التخزين الخاص.');
  return fail(prev, fallback);
}

export async function uploadGeneralDocument(prev: ActionState, form: FormData): Promise<ActionState> {
  const parsed = generalDocumentSchema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return fail(prev, parsed.error.issues[0]?.message ?? 'البيانات غير صحيحة');
  const value = parsed.data;

  const file = form.get('file');
  if (!(file instanceof File) || file.size === 0) return fail(prev, 'اختر ملفًا فعليًا.');
  if (file.size > 10 * 1024 * 1024) return fail(prev, 'حجم الملف يجب ألا يتجاوز 10 ميجابايت.');
  if (!['application/pdf', 'image/jpeg', 'image/png'].includes(file.type)) {
    return fail(prev, 'الملفات المدعومة: PDF أو JPEG أو PNG فقط.');
  }

  const bytes = Buffer.from(await file.arrayBuffer());
  const checksum = createHash('sha256').update(bytes).digest('hex');
  const objectDigest = createHash('sha256')
    .update(`${value.organizationId}|${value.idempotencyKey}|${checksum}`)
    .digest('hex');
  const objectId = `${objectDigest.slice(0, 8)}-${objectDigest.slice(8, 12)}-4${objectDigest.slice(13, 16)}-a${objectDigest.slice(17, 20)}-${objectDigest.slice(20, 32)}`;
  const objectName = `${value.organizationId}/${objectId}`;

  const supabase = await createClient();
  const uploaded = await supabase.storage.from('general-documents').upload(objectName, bytes, {
    contentType: file.type,
    upsert: false,
  });
  const alreadyUploaded = uploaded.error && /exist|duplicate/i.test(uploaded.error.message);
  if (uploaded.error && !alreadyUploaded) return domainError(prev, uploaded.error.message, 'تعذر رفع الملف الخاص.');

  const { error } = await supabase.rpc('register_general_document', {
    p_organization_id: value.organizationId,
    p_project_id: value.projectId,
    p_document_id: value.documentId,
    p_category: value.category,
    p_title: value.title,
    p_storage_object_name: objectName,
    p_original_filename: file.name,
    p_mime_type: file.type,
    p_size_bytes: file.size,
    p_sha256: checksum,
    p_idempotency_key: value.idempotencyKey,
  });
  if (error) {
    if (!alreadyUploaded) await supabase.storage.from('general-documents').remove([objectName]);
    return domainError(prev, error.message, 'تعذر تسجيل المستند.');
  }
  revalidatePath('/documents');
  return commandSuccessState(prev);
}

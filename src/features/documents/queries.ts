import { createClient } from '@/shared/supabase/server';
import { throwOperatorQuery } from '@/shared/supabase/errors';

export type GeneralDocumentRead = {
  document_id: string;
  organization_id: string;
  project_id: string | null;
  category: string;
  title: string;
  version_id: string;
  version_number: number;
  original_filename: string;
  mime_type: string;
  size_bytes: string;
  sha256: string;
  storage_bucket: string;
  storage_object_name: string;
  uploaded_by: string;
  uploaded_at: string;
  download_url: string | null;
};

const GENERAL_DOCUMENT_COLUMNS =
  'document_id,organization_id,project_id,category,title,version_id,version_number,original_filename,mime_type,size_bytes,sha256,storage_bucket,storage_object_name,uploaded_by,uploaded_at';

/** Every version of every general document in the organization, newest first, with 5-minute download links. */
export async function getOrganizationGeneralDocuments(organizationId: string): Promise<GeneralDocumentRead[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('general_documents_read')
    .select(GENERAL_DOCUMENT_COLUMNS)
    .eq('organization_id', organizationId)
    .order('uploaded_at', { ascending: false });
  if (error) throwOperatorQuery(error);
  const rows = (data ?? []) as unknown as Omit<GeneralDocumentRead, 'download_url'>[];
  if (rows.length === 0) return [];
  const { data: signed, error: signError } = await supabase.storage
    .from('general-documents')
    .createSignedUrls(rows.map((row) => row.storage_object_name), 300);
  if (signError) throwOperatorQuery(signError);
  return rows.map((row, index) => ({ ...row, download_url: signed?.[index]?.signedUrl ?? null }));
}

import { useState, type FormEvent } from 'react';
import { validateDocumentUpload } from '../../core/lib/documentFileValidation';
import type { Asset, Document, Partner, Project } from '../../core/types/domain';
import type { DocumentInput } from '../documents/storage';

export interface DocumentDraft {
  input: DocumentInput;
  file: File;
}

export function DocumentForm({
  formId,
  projects,
  assets,
  partners,
  initialProjectId,
  initialAssetId,
  initialPartnerId,
  onSubmit,
}: {
  formId: string;
  projects: Project[];
  assets: Asset[];
  partners: Partner[];
  initialProjectId?: string;
  initialAssetId?: string;
  initialPartnerId?: string;
  onSubmit: (draft: DocumentDraft) => void | Promise<void>;
}) {
  const [title, setTitle] = useState('');
  const [projectId, setProjectId] = useState(initialProjectId ?? '');
  const [assetId, setAssetId] = useState(initialAssetId ?? '');
  const [partnerId, setPartnerId] = useState(initialPartnerId ?? '');
  const [type, setType] = useState<Document['type']>('contract');
  const [issueDate, setIssueDate] = useState('');
  const [expiryDate, setExpiryDate] = useState('');
  const [notes, setNotes] = useState('');
  const [file, setFile] = useState<File>();
  const [error, setError] = useState('');
  const inputClass = 'min-h-11 w-full rounded-xl border bg-background px-3 text-sm';

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError('');
    try {
      if (!title.trim()) throw new Error('عنوان المستند مطلوب.');
      if (!projectId) throw new Error('يجب ربط المستند بمشروع.');
      if (!file) throw new Error('اختر ملف المستند.');
      validateDocumentUpload(file);
      if (issueDate && expiryDate && expiryDate < issueDate) {
        throw new Error('تاريخ الانتهاء يجب أن يكون في نفس يوم الإصدار أو بعده.');
      }
      await onSubmit({
        input: {
          title_ar: title,
          project_id: projectId,
          asset_id: assetId || undefined,
          partner_id: partnerId || undefined,
          type,
          issue_date: issueDate || undefined,
          expiry_date: expiryDate || undefined,
          notes: notes || undefined,
        },
        file,
      });
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'تعذر حفظ المستند.');
    }
  }

  return (
    <form id={formId} onSubmit={(event) => void submit(event)} className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-2">
        <label className="space-y-1 text-sm"><span>Title *</span><input className={inputClass} value={title} onChange={(event) => setTitle(event.target.value)} /></label>
        <label className="space-y-1 text-sm"><span>Type</span><select className={inputClass} value={type} onChange={(event) => setType(event.target.value as Document['type'])}><option value="contract">Contract</option><option value="invoice">Invoice</option><option value="receipt">Receipt</option><option value="ownership_deed">Ownership deed</option><option value="veterinary_record">Veterinary record</option><option value="sales_agreement">Sales agreement</option><option value="permit">Permit</option><option value="court_document">Court document</option><option value="other">Other</option></select></label>
        <label className="space-y-1 text-sm"><span>Project *</span><select className={inputClass} value={projectId} onChange={(event) => { setProjectId(event.target.value); setAssetId(''); }}><option value="">Choose project</option>{projects.map((item) => <option key={item.id} value={item.id}>{item.name_ar}</option>)}</select></label>
        <label className="space-y-1 text-sm"><span>Asset</span><select className={inputClass} value={assetId} onChange={(event) => setAssetId(event.target.value)}><option value="">No asset</option>{assets.filter((item) => !projectId || item.project_id === projectId).map((item) => <option key={item.id} value={item.id}>{item.name_ar}</option>)}</select></label>
        <label className="space-y-1 text-sm"><span>Partner</span><select className={inputClass} value={partnerId} onChange={(event) => setPartnerId(event.target.value)}><option value="">No partner</option>{partners.map((item) => <option key={item.id} value={item.id}>{item.name_ar}</option>)}</select></label>
        <label className="space-y-1 text-sm"><span>Issue date</span><input type="date" className={inputClass} value={issueDate} onChange={(event) => setIssueDate(event.target.value)} /></label>
        <label className="space-y-1 text-sm"><span>Expiry date</span><input type="date" className={inputClass} value={expiryDate} onChange={(event) => setExpiryDate(event.target.value)} /></label>
      </div>
      <label className="block space-y-1 text-sm"><span>File *</span><input type="file" accept=".pdf,.jpg,.jpeg,.png,.doc,.docx,.xls,.xlsx" className={inputClass} onChange={(event) => setFile(event.target.files?.[0])} /></label>
      <label className="block space-y-1 text-sm"><span>Notes</span><textarea className="min-h-20 w-full rounded-xl border bg-background p-3 text-sm" value={notes} onChange={(event) => setNotes(event.target.value)} /></label>
      {error && <p role="alert" className="rounded-xl border border-danger/30 bg-danger/5 p-3 text-sm text-danger">{error}</p>}
    </form>
  );
}

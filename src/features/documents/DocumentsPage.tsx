import { useState, type FormEvent } from 'react';
import { Download, Eye, FileBadge, FileCheck, FileSignature, FileText, Gavel, Plus, Trash2, Upload } from 'lucide-react';
import { PageHeader } from '../../components/layout/PageHeader';
import { Card, CardContent } from '../../components/ui/Card';
import { Button } from '../../components/ui/Button';
import { EmptyState } from '../../components/ui/States';
import { confirmSafeDeletion, guardDocumentDeletion } from '../../core/lib/deletionGuards';
import { validateDocumentUpload } from '../../core/lib/documentFileValidation';
import { deleteDocumentFile, getDocumentFile, makeLocalDocumentFileUrl, saveDocumentFile } from '../../core/storage/indexedDbFileStore';
import { usePartners } from '../partners/hooks';
import { useProjects } from '../projects/hooks';
import { useDocuments } from './hooks';
import type { DocumentInput } from './storage';
import type { Document } from '../../core/types/domain';

const TYPE_META: Record<Document['type'], { icon: typeof FileText; color: string; ar: string }> = {
  contract:          { icon: FileSignature, color: 'text-blue-600',   ar: 'عقد' },
  invoice:           { icon: FileText,      color: 'text-amber-600',  ar: 'فاتورة' },
  receipt:           { icon: FileCheck,     color: 'text-green-600',  ar: 'إيصال' },
  ownership_deed:    { icon: FileBadge,     color: 'text-purple-600', ar: 'صك ملكية' },
  veterinary_record: { icon: FileText,      color: 'text-teal-600',   ar: 'سجل بيطري' },
  sales_agreement:   { icon: FileSignature, color: 'text-orange-600', ar: 'عقد بيع' },
  permit:            { icon: FileBadge,     color: 'text-indigo-600', ar: 'تصريح' },
  court_document:    { icon: Gavel,         color: 'text-red-600',    ar: 'وثيقة قضائية' },
  other:             { icon: FileText,      color: 'text-gray-500',   ar: 'أخرى' },
};

interface DocumentDraft {
  input: DocumentInput;
  file: File;
}

function messageFrom(error: unknown) {
  return error instanceof Error ? error.message : 'تعذر تنفيذ العملية على الملف المحلي.';
}

function formatBytes(value?: number) {
  if (!value) return '';
  if (value < 1024 * 1024) return `${Math.ceil(value / 1024)} كيلوبايت`;
  return `${(value / (1024 * 1024)).toFixed(1)} ميجابايت`;
}

function DocForm({ projects, partners, onSubmit, onCancel }: {
  projects: ReturnType<typeof useProjects>['projects'];
  partners: ReturnType<typeof usePartners>['partners'];
  onSubmit: (draft: DocumentDraft) => Promise<void>;
  onCancel: () => void;
}) {
  const [title_ar, setTitle] = useState('');
  const [project_id, setProjectId] = useState('');
  const [partner_id, setPartnerId] = useState('');
  const [type, setType] = useState<Document['type']>('contract');
  const [issue_date, setIssueDate] = useState('');
  const [expiry_date, setExpiryDate] = useState('');
  const [notes, setNotes] = useState('');
  const [file, setFile] = useState<File>();
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);

  const ic = 'block w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary';
  const lc = 'mb-1 block text-sm font-medium text-foreground';

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setError('');
    try {
      if (!title_ar.trim()) throw new Error('عنوان المستند مطلوب.');
      if (!project_id) throw new Error('اختر المشروع المرتبط بالمستند.');
      if (!file) throw new Error('اختر صورة أو ملف المستند قبل الحفظ.');
      validateDocumentUpload(file);
      setSaving(true);
      await onSubmit({
        input: {
          title_ar,
          project_id,
          partner_id: partner_id || undefined,
          type,
          issue_date: issue_date || undefined,
          expiry_date: expiry_date || undefined,
          notes: notes || undefined,
        },
        file,
      });
    } catch (submitError) {
      setError(messageFrom(submitError));
    } finally {
      setSaving(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className={lc}>عنوان المستند *</label>
          <input className={ic} value={title_ar} onChange={event => setTitle(event.target.value)} placeholder="عقد شراكة مشروع المرسى" />
        </div>
        <div>
          <label className={lc}>نوع المستند</label>
          <select className={ic} value={type} onChange={event => setType(event.target.value as Document['type'])}>
            {Object.entries(TYPE_META).map(([id, meta]) => <option key={id} value={id}>{meta.ar}</option>)}
          </select>
        </div>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className={lc}>المشروع المرتبط *</label>
          <select className={ic} value={project_id} onChange={event => setProjectId(event.target.value)}>
            <option value="">اختر المشروع</option>
            {projects.map(project => <option key={project.id} value={project.id}>{project.name_ar}</option>)}
          </select>
        </div>
        <div>
          <label className={lc}>الطرف أو الشريك المرتبط</label>
          <select className={ic} value={partner_id} onChange={event => setPartnerId(event.target.value)}>
            <option value="">بدون طرف محدد</option>
            {partners.map(partner => <option key={partner.id} value={partner.id}>{partner.name_ar}</option>)}
          </select>
        </div>
      </div>
      <div>
        <label className={lc}>صورة أو ملف المستند *</label>
        <input
          type="file"
          accept=".pdf,.jpg,.jpeg,.png,.doc,.docx,.xls,.xlsx"
          className={ic}
          onChange={event => setFile(event.target.files?.[0])}
        />
        <p className="mt-1 text-xs text-muted-foreground">PDF أو صورة أو Word أو Excel، بحد أقصى 10 ميجابايت. يُحفظ الملف محليًا على هذا الجهاز.</p>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label className={lc}>تاريخ الإصدار</label>
          <input type="date" className={ic} value={issue_date} onChange={event => setIssueDate(event.target.value)} />
        </div>
        <div>
          <label className={lc}>تاريخ الانتهاء</label>
          <input type="date" className={ic} value={expiry_date} onChange={event => setExpiryDate(event.target.value)} />
        </div>
      </div>
      <div>
        <label className={lc}>ملاحظات</label>
        <textarea className={ic} rows={2} value={notes} onChange={event => setNotes(event.target.value)} />
      </div>
      {error && <p className="rounded-xl border border-danger/30 bg-danger/10 px-3 py-2 text-sm text-danger">{error}</p>}
      <div className="flex flex-col gap-3 min-[360px]:flex-row min-[360px]:justify-end">
        <Button type="button" variant="secondary" onClick={onCancel} disabled={saving}>إلغاء</Button>
        <Button type="submit" disabled={saving}>
          <Upload className="h-4 w-4" /> {saving ? 'جار الحفظ…' : 'رفع وحفظ المستند'}
        </Button>
      </div>
    </form>
  );
}

export function DocumentsPage() {
  const { documents, createDocument, updateDocument, deleteDocument } = useDocuments();
  const { projects } = useProjects();
  const { partners } = usePartners();
  const [showForm, setShowForm] = useState(false);
  const [filterType, setFilterType] = useState<Document['type'] | 'all'>('all');
  const projectNames = new Map(projects.map(project => [project.id, project.name_ar]));
  const partnerNames = new Map(partners.map(partner => [partner.id, partner.name_ar]));

  const filtered = filterType === 'all' ? documents : documents.filter(document => document.type === filterType);

  async function rollbackCreatedDocument(document: Document) {
    try {
      await deleteDocumentFile(makeLocalDocumentFileUrl(document.id));
    } catch {
      // Keep the original upload failure visible to the user.
    }
    try {
      deleteDocument(document.id);
    } catch {
      // Keep the original upload failure visible to the user.
    }
  }

  async function handleCreateDocument({ input, file }: DocumentDraft) {
    const document = createDocument(input);
    try {
      const storedFile = await saveDocumentFile(document.id, file);
      updateDocument(document.id, {
        file_url: makeLocalDocumentFileUrl(document.id),
        file_name: storedFile.original_file_name,
        file_mime_type: storedFile.mime_type,
        file_size_bytes: storedFile.size_bytes,
        file_sha256: storedFile.sha256,
      });
      setShowForm(false);
    } catch (error) {
      await rollbackCreatedDocument(document);
      throw error;
    }
  }

  async function handleOpenDocument(document: Document, download: boolean) {
    if (!document.file_url) {
      window.alert('هذا سجل قديم ولا يحتوي على ملف محلي مرفوع.');
      return;
    }
    try {
      const storedFile = await getDocumentFile(document.file_url);
      if (!storedFile) throw new Error('الملف المحلي غير موجود على هذا الجهاز.');
      const url = URL.createObjectURL(storedFile.blob);
      if (download) {
        const link = window.document.createElement('a');
        link.href = url;
        link.download = document.file_name || storedFile.original_file_name;
        link.click();
        window.setTimeout(() => URL.revokeObjectURL(url), 1000);
      } else {
        window.open(url, '_blank', 'noopener,noreferrer');
        window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
      }
    } catch (error) {
      window.alert(messageFrom(error));
    }
  }

  async function handleDeleteDocument(document: Document) {
    const guard = guardDocumentDeletion(document.id);
    if (!guard.canDelete) {
      window.alert(guard.message_ar);
      return;
    }
    if (!confirmSafeDeletion(guard.message_ar)) return;
    try {
      deleteDocument(document.id);
    } catch (error) {
      window.alert(messageFrom(error));
      return;
    }
    if (!document.file_url) return;
    try {
      await deleteDocumentFile(document.file_url);
    } catch {
      window.alert('تم حذف سجل المستند، لكن تعذر حذف نسخة الملف المحلية من هذا الجهاز.');
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader title="إدارة المستندات" description="ارفع صور العقود ومستندات الشراكة والفواتير واربطها بالمشروع والطرف المعني.">
        <Button onClick={() => setShowForm(true)}>
          <Plus className="h-4 w-4" /> رفع مستند
        </Button>
      </PageHeader>

      {showForm && (
        <Card>
          <CardContent>
            <h3 className="mb-4 text-base font-semibold">رفع مستند جديد</h3>
            <DocForm projects={projects} partners={partners} onSubmit={handleCreateDocument} onCancel={() => setShowForm(false)} />
          </CardContent>
        </Card>
      )}

      <div className="flex flex-wrap gap-2">
        <button onClick={() => setFilterType('all')} className={`rounded-full border px-3 py-1 text-xs font-medium transition ${filterType === 'all' ? 'border-primary bg-primary/10 text-primary' : 'border-border text-muted-foreground hover:bg-muted'}`}>الكل</button>
        {Object.entries(TYPE_META).map(([id, meta]) => (
          <button key={id} onClick={() => setFilterType(id as Document['type'])} className={`rounded-full border px-3 py-1 text-xs font-medium transition ${filterType === id ? 'border-primary bg-primary/10 text-primary' : 'border-border text-muted-foreground hover:bg-muted'}`}>{meta.ar}</button>
        ))}
      </div>

      {filtered.length === 0 ? (
        <EmptyState title="لا توجد مستندات بعد" description="ارفع أول صورة أو ملف لعقد أو مستند شراكة لتبدأ." />
      ) : (
        <Card>
          <div className="divide-y divide-border">
            {filtered.map(document => {
              const meta = TYPE_META[document.type];
              const Icon = meta.icon;
              return (
                <div key={document.id} className="flex flex-col gap-3 px-4 py-3 transition hover:bg-muted/50 lg:flex-row lg:items-center">
                  <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-border bg-muted">
                    <Icon className={`h-5 w-5 ${meta.color}`} />
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium">{document.title_ar}</p>
                    <p className="text-xs text-muted-foreground">
                      {meta.ar} • {document.project_id ? projectNames.get(document.project_id) ?? 'مشروع غير معروف' : 'بدون مشروع'}
                      {document.partner_id ? ` • ${partnerNames.get(document.partner_id) ?? 'طرف غير معروف'}` : ''}
                    </p>
                    <p className="mt-1 truncate text-xs text-muted-foreground">
                      {document.file_name ? `${document.file_name}${document.file_size_bytes ? ` • ${formatBytes(document.file_size_bytes)}` : ''}` : 'سجل قديم بدون ملف محلي'}
                    </p>
                  </div>
                  {document.expiry_date && <span className="text-xs text-muted-foreground">ينتهي {document.expiry_date}</span>}
                  <div className="flex flex-wrap gap-2">
                    <Button variant="secondary" size="sm" onClick={() => void handleOpenDocument(document, false)} disabled={!document.file_url}>
                      <Eye className="h-4 w-4" /> فتح
                    </Button>
                    <Button variant="secondary" size="sm" onClick={() => void handleOpenDocument(document, true)} disabled={!document.file_url}>
                      <Download className="h-4 w-4" /> تنزيل
                    </Button>
                    <Button variant="danger" size="sm" onClick={() => void handleDeleteDocument(document)}>
                      <Trash2 className="h-4 w-4" /> حذف
                    </Button>
                  </div>
                </div>
              );
            })}
          </div>
        </Card>
      )}
    </div>
  );
}

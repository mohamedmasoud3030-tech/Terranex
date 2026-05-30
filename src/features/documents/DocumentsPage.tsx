import { useState } from 'react';
import { Plus, FileText, FileCheck, FileSignature, FileBadge, Gavel } from 'lucide-react';
import { PageHeader } from '../../components/layout/PageHeader';
import { Card, CardContent } from '../../components/ui/Card';
import { Button } from '../../components/ui/Button';
import { EmptyState } from '../../components/ui/States';
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

function DocForm({ onSubmit, onCancel }: { onSubmit: (i: DocumentInput) => void; onCancel: () => void }) {
  const [title_ar, setTitle] = useState('');
  const [type, setType] = useState<Document['type']>('contract');
  const [issue_date, setIssueDate] = useState('');
  const [expiry_date, setExpiryDate] = useState('');
  const [notes, setNotes] = useState('');

  const ic = 'block w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary';
  const lc = 'block text-sm font-medium text-foreground mb-1';

  return (
    <form onSubmit={e => { e.preventDefault(); if (title_ar.trim()) { onSubmit({ title_ar, type, issue_date: issue_date || undefined, expiry_date: expiry_date || undefined, notes: notes || undefined }); }}} className="space-y-4">
      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className={lc}>عنوان المستند *</label>
          <input className={ic} value={title_ar} onChange={e => setTitle(e.target.value)} placeholder="عقد شراء أرض المرسى" />
        </div>
        <div>
          <label className={lc}>نوع المستند</label>
          <select className={ic} value={type} onChange={e => setType(e.target.value as Document['type'])}>
            {Object.entries(TYPE_META).map(([id, m]) => <option key={id} value={id}>{m.ar}</option>)}
          </select>
        </div>
      </div>
      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className={lc}>تاريخ الإصدار</label>
          <input type="date" className={ic} value={issue_date} onChange={e => setIssueDate(e.target.value)} />
        </div>
        <div>
          <label className={lc}>تاريخ الانتهاء</label>
          <input type="date" className={ic} value={expiry_date} onChange={e => setExpiryDate(e.target.value)} />
        </div>
      </div>
      <div>
        <label className={lc}>ملاحظات</label>
        <textarea className={ic} rows={2} value={notes} onChange={e => setNotes(e.target.value)} />
      </div>
      <div className="flex gap-3 justify-end">
        <Button type="button" variant="secondary" onClick={onCancel}>إلغاء</Button>
        <Button type="submit">حفظ المستند</Button>
      </div>
    </form>
  );
}

export function DocumentsPage() {
  const { documents, createDocument } = useDocuments();
  const [showForm, setShowForm] = useState(false);
  const [filterType, setFilterType] = useState<Document['type'] | 'all'>('all');

  const filtered = filterType === 'all' ? documents : documents.filter(d => d.type === filterType);

  return (
    <div className="space-y-6">
      <PageHeader
        title="إدارة المستندات"
        description="كل مشروع هو حاوية الأصول والمعاملات والمستندات والشركاء."
        children={<Button onClick={() => setShowForm(true)}
      /> مستند جديد</Button>}
      />

      {showForm && (
        <Card><CardContent>
          <h3 className="mb-4 text-base font-semibold">مستند جديد</h3>
          <DocForm onSubmit={d => { createDocument(d); setShowForm(false); }} onCancel={() => setShowForm(false)} />
        </CardContent></Card>
      )}

      {/* Type filter */}
      <div className="flex flex-wrap gap-2">
        <button onClick={() => setFilterType('all')} className={`rounded-full border px-3 py-1 text-xs font-medium transition ${filterType === 'all' ? 'border-primary bg-primary/10 text-primary' : 'border-border text-muted-foreground hover:bg-muted'}`}>الكل</button>
        {Object.entries(TYPE_META).map(([id, m]) => (
          <button key={id} onClick={() => setFilterType(id as Document['type'])} className={`rounded-full border px-3 py-1 text-xs font-medium transition ${filterType === id ? 'border-primary bg-primary/10 text-primary' : 'border-border text-muted-foreground hover:bg-muted'}`}>{m.ar}</button>
        ))}
      </div>

      {filtered.length === 0 ? (
        <EmptyState title="لا توجد بيانات بعد" description="أضف أول سجل لهذا القسم لتبدأ." />
      ) : (
        <Card>
          <div className="divide-y divide-border">
            {filtered.map(doc => {
              const meta = TYPE_META[doc.type];
              const Icon = meta.icon;
              return (
                <div key={doc.id} className="flex items-center gap-4 px-4 py-3 hover:bg-muted/50 transition">
                  <div className="flex h-10 w-10 items-center justify-center rounded-xl border border-border bg-muted">
                    <Icon className={`h-5 w-5 ${meta.color}`} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{doc.title_ar}</p>
                    <p className="text-xs text-muted-foreground">{meta.ar} {doc.issue_date ? `• ${doc.issue_date}` : ''}</p>
                  </div>
                  {doc.expiry_date && (
                    <span className="text-xs text-muted-foreground">ينتهي {doc.expiry_date}</span>
                  )}
                </div>
              );
            })}
          </div>
        </Card>
      )}
    </div>
  );
}

import { Plus, Trash2 } from 'lucide-react';
import { useState, type FormEvent } from 'react';
import { Button } from '../../components/ui/Button';
import { FormError, FormField, FormHint, FormLabel } from '../../components/ui/FormControls';
import { useI18n } from '../../core/i18n/context';
import type { BankAccount, Currency, Partner, Project } from '../../core/types/domain';
import { createInvoice, type InvoiceInput } from './storage';

interface Props {
  projects: Project[];
  partners: Partner[];
  bankAccounts: BankAccount[];
  defaultCurrency: Currency;
  defaultVatRate: number;
  onCancel: () => void;
  onSaved: () => void | Promise<void>;
}

interface DraftLine {
  id: string;
  description_ar: string;
  description_en: string;
  quantity: number;
  unit_price: number;
}

function newLine(): DraftLine {
  return { id: crypto.randomUUID(), description_ar: '', description_en: '', quantity: 1, unit_price: 0 };
}

export function InvoiceForm({ projects, partners, bankAccounts, defaultCurrency, defaultVatRate, onCancel, onSaved }: Props) {
  const { locale } = useI18n();
  const [projectId, setProjectId] = useState('');
  const [partnerId, setPartnerId] = useState('');
  const [bankAccountId, setBankAccountId] = useState('');
  const [currency, setCurrency] = useState<Currency>(defaultCurrency);
  const [fx, setFx] = useState('1');
  const [issueDate, setIssueDate] = useState(new Date().toISOString().slice(0, 10));
  const [dueDate, setDueDate] = useState('');
  const [vatRate, setVatRate] = useState(String(defaultVatRate));
  const [notes, setNotes] = useState('');
  const [lines, setLines] = useState<DraftLine[]>([newLine()]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const activeBanks = bankAccounts.filter(a => !a.is_archived);

  const subtotal = lines.reduce((s, l) => s + (Number(l.quantity) || 0) * (Number(l.unit_price) || 0), 0);
  const vat = Math.round(subtotal * (Number(vatRate) || 0)) / 100;
  const total = Math.round((subtotal + vat) * 1000) / 1000;

  function updateLine(id: string, patch: Partial<DraftLine>) {
    setLines(cur => cur.map(l => l.id === id ? { ...l, ...patch } : l));
  }
  function removeLine(id: string) {
    setLines(cur => cur.length > 1 ? cur.filter(l => l.id !== id) : cur);
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    if (!partnerId) { setError(locale === 'ar' ? 'اختر العميل.' : 'Select a customer.'); return; }
    const fxN = Number(fx);
    if (!Number.isFinite(fxN) || fxN <= 0) { setError(locale === 'ar' ? 'سعر الصرف غير صالح.' : 'Invalid FX rate.'); return; }
    const validLines = lines.filter(l => l.description_ar.trim() && Number(l.quantity) > 0 && Number(l.unit_price) >= 0);
    if (validLines.length === 0) { setError(locale === 'ar' ? 'أضف بنداً واحداً على الأقل.' : 'Add at least one line.'); return; }

    setSaving(true);
    try {
      const input: InvoiceInput = {
        project_id: projectId || undefined,
        partner_id: partnerId,
        bank_account_id: bankAccountId || undefined,
        issue_date: issueDate,
        due_date: dueDate || undefined,
        currency,
        fx_rate_to_base: fxN,
        vat_rate: Number(vatRate) || 0,
        notes: notes.trim() || undefined,
        lines: validLines.map(l => ({
          description_ar: l.description_ar.trim(),
          description_en: l.description_en.trim() || undefined,
          quantity: Number(l.quantity),
          unit_price: Number(l.unit_price),
        })),
      };
      await createInvoice(input);
      await onSaved();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setSaving(false);
    }
  }

  const cell = 'min-h-10 rounded-lg border border-border bg-background px-2 py-1.5 text-sm';

  return (
    <form onSubmit={submit} className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-2">
        <FormField>
          <FormLabel>{locale === 'ar' ? 'العميل' : 'Customer'} *</FormLabel>
          <select value={partnerId} onChange={e => setPartnerId(e.target.value)} className={`${cell} w-full`}>
            <option value="">{locale === 'ar' ? 'اختر عميلاً…' : 'Choose customer…'}</option>
            {partners.map(p => <option key={p.id} value={p.id}>{p.name_ar}{p.name_en ? ` (${p.name_en})` : ''}</option>)}
          </select>
        </FormField>
        <FormField>
          <FormLabel>{locale === 'ar' ? 'المشروع' : 'Project'}</FormLabel>
          <select value={projectId} onChange={e => setProjectId(e.target.value)} className={`${cell} w-full`}>
            <option value="">{locale === 'ar' ? 'بدون مشروع' : 'No project'}</option>
            {projects.map(p => <option key={p.id} value={p.id}>{p.name_ar}</option>)}
          </select>
        </FormField>
        <FormField>
          <FormLabel>{locale === 'ar' ? 'الحساب البنكي / الصندوق' : 'Bank / Cash account'}</FormLabel>
          <select value={bankAccountId} onChange={e => setBankAccountId(e.target.value)} className={`${cell} w-full`}>
            <option value="">{locale === 'ar' ? 'آجل (لا يوجد حساب)' : 'On credit'}</option>
            {activeBanks.map(a => <option key={a.id} value={a.id}>{a.currency} — {a.name_ar}</option>)}
          </select>
        </FormField>
        <FormField>
          <FormLabel>{locale === 'ar' ? 'العملة' : 'Currency'}</FormLabel>
          <select value={currency} onChange={e => setCurrency(e.target.value as Currency)} className={`${cell} w-full`}>
            {['OMR','EGP','USD','SAR','AED','EUR','GBP'].map(c => <option key={c} value={c}>{c}</option>)}
          </select>
        </FormField>
        <FormField>
          <FormLabel>{locale === 'ar' ? 'تاريخ الإصدار' : 'Issue date'} *</FormLabel>
          <input type="date" value={issueDate} onChange={e => setIssueDate(e.target.value)} className={`${cell} w-full`} />
        </FormField>
        <FormField>
          <FormLabel>{locale === 'ar' ? 'تاريخ الاستحقاق' : 'Due date'}</FormLabel>
          <input type="date" value={dueDate} onChange={e => setDueDate(e.target.value)} className={`${cell} w-full`} />
        </FormField>
        <FormField>
          <FormLabel>{locale === 'ar' ? 'سعر الصرف' : 'FX rate'}</FormLabel>
          <input type="number" step="0.0001" min="0" value={fx} onChange={e => setFx(e.target.value)} className={`${cell} w-full`} dir="ltr" />
          {currency !== defaultCurrency && <FormHint>1 {currency} = {fx} {defaultCurrency}</FormHint>}
        </FormField>
        <FormField>
          <FormLabel>{locale === 'ar' ? 'نسبة الضريبة %' : 'VAT rate %'}</FormLabel>
          <input type="number" step="0.01" min="0" max="100" value={vatRate} onChange={e => setVatRate(e.target.value)} className={`${cell} w-full`} dir="ltr" />
        </FormField>
      </div>

      <div>
        <div className="mb-2 flex items-center justify-between">
          <FormLabel>{locale === 'ar' ? 'بنود الفاتورة' : 'Invoice lines'} *</FormLabel>
          <Button type="button" variant="secondary" size="sm" onClick={() => setLines(cur => [...cur, newLine()])}>
            <Plus className="h-3.5 w-3.5" /> {locale === 'ar' ? 'بند' : 'Line'}
          </Button>
        </div>
        <div className="space-y-2">
          {lines.map((l, idx) => (
            <div key={l.id} className="grid grid-cols-12 gap-2 items-start">
              <input value={l.description_ar} onChange={e => updateLine(l.id, { description_ar: e.target.value })} className={`${cell} col-span-6`} placeholder={locale === 'ar' ? 'وصف البند (عربي)' : 'Description'} />
              <input type="number" min="0" step="0.001" value={l.quantity} onChange={e => updateLine(l.id, { quantity: Number(e.target.value) })} className={`${cell} col-span-2`} dir="ltr" placeholder={locale === 'ar' ? 'الكمية' : 'Qty'} />
              <input type="number" min="0" step="0.001" value={l.unit_price} onChange={e => updateLine(l.id, { unit_price: Number(e.target.value) })} className={`${cell} col-span-3`} dir="ltr" placeholder={locale === 'ar' ? 'سعر الوحدة' : 'Unit price'} />
              <button type="button" onClick={() => removeLine(l.id)} className="col-span-1 flex h-10 items-center justify-center rounded-lg border border-border text-muted-foreground hover:text-danger disabled:opacity-50" disabled={lines.length === 1}>
                <Trash2 className="h-4 w-4" />
              </button>
            </div>
          ))}
        </div>
      </div>

      <div className="rounded-xl border border-border bg-muted/30 p-3 text-sm">
        <div className="flex justify-between"><span>{locale === 'ar' ? 'المجموع الفرعي' : 'Subtotal'}</span><span>{subtotal.toFixed(3)} {currency}</span></div>
        <div className="flex justify-between"><span>{locale === 'ar' ? `ضريبة (${vatRate}%)` : `VAT (${vatRate}%)`}</span><span>{vat.toFixed(3)} {currency}</span></div>
        <div className="mt-1 flex justify-between border-t pt-1 font-bold"><span>{locale === 'ar' ? 'الإجمالي' : 'Total'}</span><span>{total.toFixed(3)} {currency}</span></div>
      </div>

      <FormField>
        <FormLabel>{locale === 'ar' ? 'ملاحظات' : 'Notes'}</FormLabel>
        <textarea rows={2} value={notes} onChange={e => setNotes(e.target.value)} className={`${cell} w-full`} />
      </FormField>

      {error && <FormError>{error}</FormError>}

      <div className="flex justify-end gap-2 pt-2">
        <Button type="button" variant="secondary" onClick={onCancel} disabled={saving}>{locale === 'ar' ? 'إلغاء' : 'Cancel'}</Button>
        <Button type="submit" disabled={saving}>{saving ? (locale === 'ar' ? 'جارٍ الحفظ…' : 'Saving…') : (locale === 'ar' ? 'حفظ كمسودة' : 'Save draft')}</Button>
      </div>
    </form>
  );
}

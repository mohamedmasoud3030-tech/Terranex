import { BookOpenText, CheckCircle2, FilePlus, Plus, Trash2 } from 'lucide-react';
import { useRouter } from '@tanstack/react-router';
import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react';
import { PageHeader } from '../../components/layout/PageHeader';
import { Button } from '../../components/ui/Button';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { Badge } from '../../components/ui/Badge';
import { FormError, FormField, FormLabel } from '../../components/ui/FormControls';
import { ModalOverlay } from '../../components/ui/ModalOverlay';
import { useI18n } from '../../core/i18n/context';
import { formatMoney } from '../../core/lib/format';
import type { BankAccount, Currency, JournalEntry, JournalEntryLine, Partner, Project } from '../../core/types/domain';
import { useBankAccounts, useCompanySettings } from '../banking/hooks';
import { useProjects } from '../projects/hooks';
import { usePartners } from '../partners/hooks';
import {
  createJournalEntry,
  listJournalEntries,
  listJournalEntryLines,
  postJournalEntry,
  voidJournalEntry,
  type JournalEntryInput,
} from './journalStorage';

interface DraftLine {
  id: string;
  account_code: string;
  description_ar: string;
  debit: string;
  credit: string;
  bank_account_id: string;
  partner_id: string;
  project_id: string;
}
function newLine(): DraftLine {
  return {
    id: crypto.randomUUID(),
    account_code: '',
    description_ar: '',
    debit: '',
    credit: '',
    bank_account_id: '',
    partner_id: '',
    project_id: '',
  };
}

const STATUS_TONE: Record<string, 'positive' | 'warning' | 'negative' | 'neutral'> = {
  draft: 'neutral',
  posted: 'positive',
  reversed: 'warning',
  void: 'negative',
};
function statusLabel(locale: 'ar' | 'en', s: string) {
  const m: Record<string, string> = {
    draft: locale === 'ar' ? 'مسودة' : 'Draft',
    posted: locale === 'ar' ? 'مرحّل' : 'Posted',
    reversed: locale === 'ar' ? 'معكوس' : 'Reversed',
    void: locale === 'ar' ? 'ملغى' : 'Void',
  };
  return m[s] ?? s;
}

function voidActionTitle(locale: 'ar' | 'en', status: JournalEntry['status']) {
  if (status === 'posted') return locale === 'ar' ? 'إنشاء سند عكسي' : 'Create reversal';
  return locale === 'ar' ? 'إلغاء المسودة' : 'Void draft';
}

export function JournalPage() {
  const router = useRouter();
  const { t, locale } = useI18n();
  const { accounts } = useBankAccounts();
  const { projects } = useProjects();
  const { partners } = usePartners();
  const { settings } = useCompanySettings();

  const [entries, setEntries] = useState<JournalEntry[]>([]);
  const [entryLines, setEntryLines] = useState<Record<string, JournalEntryLine[]>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [dialog, setDialog] = useState<null | 'create' | { kind: 'view'; id: string }>(null);
  const [actionPending, setActionPending] = useState(false);

  const baseCurrency: Currency = (settings?.base_currency as Currency) ?? 'OMR';
  const activeBanks = useMemo(() => accounts.filter(a => !a.is_archived), [accounts]);

  // Form state
  const [formDate, setFormDate] = useState(new Date().toISOString().slice(0, 10));
  const [formDesc, setFormDesc] = useState('');
  const [formCurrency, setFormCurrency] = useState<Currency>(baseCurrency);
  const [formFx, setFormFx] = useState('1');
  const [formNotes, setFormNotes] = useState('');
  const [formLines, setFormLines] = useState<DraftLine[]>([newLine(), newLine()]);
  const [formError, setFormError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      const rows = await listJournalEntries();
      setEntries(rows);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  async function openView(id: string) {
    if (!entryLines[id]) {
      try {
        const ls = await listJournalEntryLines(id);
        setEntryLines(cur => ({ ...cur, [id]: ls }));
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e));
        return;
      }
    }
    setDialog({ kind: 'view', id });
  }

  async function handlePost(id: string) {
    setActionPending(true);
    try { await postJournalEntry(id); await refresh(); }
    catch (e) { setError(e instanceof Error ? e.message : String(e)); }
    finally { setActionPending(false); }
  }
  async function handleVoid(id: string) {
    setActionPending(true);
    try { await voidJournalEntry(id); await refresh(); }
    catch (e) { setError(e instanceof Error ? e.message : String(e)); }
    finally { setActionPending(false); }
  }

  function updateLine(id: string, patch: Partial<DraftLine>) {
    setFormLines(cur => cur.map(l => l.id === id ? { ...l, ...patch } : l));
  }
  function removeLine(id: string) {
    setFormLines(cur => cur.length > 2 ? cur.filter(l => l.id !== id) : cur);
  }

  async function submitCreate(e: FormEvent) {
    e.preventDefault();
    setFormError(null);
    const fx = Number(formFx);
    if (!Number.isFinite(fx) || fx <= 0) { setFormError(locale === 'ar' ? 'سعر الصرف غير صالح.' : 'Invalid FX.'); return; }
    const valid = formLines.filter(l => Number(l.debit) > 0 || Number(l.credit) > 0);
    if (valid.length < 2) { setFormError(locale === 'ar' ? 'أضف بندين على الأقل (مدين ودائن).' : 'At least two lines required.'); return; }
    const tD = valid.reduce((s, l) => s + Number(l.debit || 0), 0);
    const tC = valid.reduce((s, l) => s + Number(l.credit || 0), 0);
    if (Math.abs(tD - tC) > 0.001) {
      setFormError(locale === 'ar' ? `القيد غير متوازن: مدين ${tD.toFixed(3)} / دائن ${tC.toFixed(3)}` : `Unbalanced: debit ${tD.toFixed(3)} / credit ${tC.toFixed(3)}`);
      return;
    }

    setSaving(true);
    try {
      const input: JournalEntryInput = {
        entry_date: formDate,
        description_ar: formDesc.trim() || undefined,
        currency: formCurrency,
        fx_rate_to_base: fx,
        notes: formNotes.trim() || undefined,
        lines: valid.map(l => ({
          account_code: l.account_code.trim() || undefined,
          description_ar: l.description_ar.trim() || undefined,
          debit: Number(l.debit) || 0,
          credit: Number(l.credit) || 0,
          bank_account_id: l.bank_account_id || undefined,
          partner_id: l.partner_id || undefined,
          project_id: l.project_id || undefined,
        })),
      };
      await createJournalEntry(input);
      setDialog(null);
      resetForm();
      await refresh();
    } catch (err) {
      setFormError(err instanceof Error ? err.message : String(err));
    } finally {
      setSaving(false);
    }
  }

  function resetForm() {
    setFormDate(new Date().toISOString().slice(0, 10));
    setFormDesc('');
    setFormCurrency(baseCurrency);
    setFormFx('1');
    setFormNotes('');
    setFormLines([newLine(), newLine()]);
    setFormError(null);
  }

  const totalD = formLines.reduce((s, l) => s + Number(l.debit || 0), 0);
  const totalC = formLines.reduce((s, l) => s + Number(l.credit || 0), 0);
  const balanced = Math.abs(totalD - totalC) < 0.001 && totalD > 0;

  const totalPostedDebit = entries.filter(e => e.status === 'posted').reduce((s, e) => s + e.total_debit, 0);

  const cell = 'min-h-10 rounded-lg border border-border bg-background px-2 py-1.5 text-sm';

  const viewingEntry = dialog && typeof dialog === 'object' && dialog.kind === 'view'
    ? entries.find(e => e.id === dialog.id) ?? null : null;
  const viewingLines = viewingEntry ? (entryLines[viewingEntry.id] ?? []) : [];

  return (
    <div className="space-y-6">
      <PageHeader
        title={locale === 'ar' ? 'سندات محاسبية يدوية' : 'Manual Accounting Vouchers'}
        description={locale === 'ar'
          ? 'سندات مدين/دائن يدوية مع أثر بنكي ذرّي. ليست دفتر أستاذ عامًا ولا دليل حسابات معتمدًا.'
          : 'Balanced manual debit/credit vouchers with atomic bank effects; not an authoritative general ledger or chart of accounts.'}
      >
        <Button onClick={() => router.navigate({ to: '/finance' } as any)} variant="secondary">
          <BookOpenText className="h-4 w-4" /> {locale === 'ar' ? 'المالية' : 'Finance'}
        </Button>
        <Button onClick={() => { resetForm(); setDialog('create'); }}>
          <FilePlus className="h-4 w-4" /> {locale === 'ar' ? 'سند جديد' : 'New voucher'}
        </Button>
      </PageHeader>

      {error && (
        <div className="rounded-2xl border border-danger/30 bg-danger/5 px-4 py-3 text-sm text-danger">{error}</div>
      )}

      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'إجمالي السندات' : 'Total vouchers'}</p><p className="text-xl font-bold">{entries.length}</p></CardContent></Card>
        <Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'مرحّلة' : 'Posted'}</p><p className="text-xl font-bold text-success">{entries.filter(e => e.status === 'posted').length}</p></CardContent></Card>
        <Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'مسودات' : 'Drafts'}</p><p className="text-xl font-bold">{entries.filter(e => e.status === 'draft').length}</p></CardContent></Card>
        <Card><CardContent className="p-4"><p className="text-xs text-muted-foreground">{locale === 'ar' ? 'إجمالي الحركات المرحلة' : 'Posted volume'}</p><p className="text-xl font-bold">{formatMoney(totalPostedDebit, baseCurrency, locale)}</p></CardContent></Card>
      </div>

      <Card>
        <CardHeader><h3 className="font-semibold">{locale === 'ar' ? 'قائمة السندات' : 'Voucher list'}</h3></CardHeader>
        <CardContent className="p-0">
          {loading ? (
            <p className="px-4 py-8 text-center text-sm text-muted-foreground">{t('state_loading')}</p>
          ) : entries.length === 0 ? (
            <p className="px-4 py-8 text-center text-sm text-muted-foreground">{locale === 'ar' ? 'لا توجد سندات بعد.' : 'No vouchers yet.'}</p>
          ) : (
            <div className="divide-y divide-border">
              {entries.map(e => {
                const isBalanced = Math.abs(e.total_debit - e.total_credit) < 0.001;
                return (
                  <div key={e.id} className="flex min-h-14 w-full items-center gap-3 px-4 py-3 hover:bg-muted/50">
                    <button type="button" onClick={() => openView(e.id)} className="flex flex-1 min-w-0 items-center gap-3 text-start">
                      <div className="flex h-9 w-9 items-center justify-center rounded-lg border border-primary/20 bg-primary/5">
                        <BookOpenText className="h-4 w-4 text-primary" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium truncate">{e.entry_number} {e.description_ar && <span className="text-muted-foreground">— {e.description_ar}</span>}</p>
                        <p className="text-xs text-muted-foreground">{e.entry_date} • {formatMoney(e.total_debit, e.currency, locale)} {!isBalanced && e.status === 'draft' && <span className="text-danger">• {locale === 'ar' ? 'غير متوازن' : 'unbalanced'}</span>}</p>
                      </div>
                      <Badge tone={STATUS_TONE[e.status] ?? 'neutral'}>{statusLabel(locale, e.status)}</Badge>
                    </button>
                    <div className="flex gap-1">
                      {e.status === 'draft' && (
                        <button type="button" onClick={() => handlePost(e.id)} disabled={actionPending} title={locale === 'ar' ? 'ترحيل' : 'Post'}
                          className="rounded-lg p-2 text-muted-foreground hover:bg-success/10 hover:text-success disabled:opacity-50">
                          <CheckCircle2 className="h-4 w-4" />
                        </button>
                      )}
                      {(e.status === 'draft' || e.status === 'posted') && (
                        <button type="button" onClick={() => handleVoid(e.id)} disabled={actionPending} title={voidActionTitle(locale, e.status)}
                          className="rounded-lg p-2 text-muted-foreground hover:bg-danger/10 hover:text-danger disabled:opacity-50">
                          <Trash2 className="h-4 w-4" />
                        </button>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </CardContent>
      </Card>

      {/* View detail */}
      {viewingEntry && (
        <ModalOverlay closeLabel={locale === 'ar' ? 'إغلاق السند' : 'Close voucher'} onClose={() => setDialog(null)} placement="start" contentClassName="my-8 w-full max-w-3xl rounded-2xl bg-card p-6 shadow-xl space-y-3">
            <h3 className="font-semibold">{viewingEntry.entry_number}</h3>
            <p className="text-sm text-muted-foreground">{viewingEntry.entry_date} • {viewingEntry.currency} • {statusLabel(locale, viewingEntry.status)}</p>
            {viewingEntry.description_ar && <p className="text-sm">{viewingEntry.description_ar}</p>}
            <div className="overflow-x-auto rounded-lg border">
              <table className="w-full text-sm">
                <thead className="bg-muted/50 text-xs">
                  <tr><th className="px-3 py-2 text-start">{locale === 'ar' ? 'الحساب' : 'Account'}</th><th className="px-3 py-2 text-start">{locale === 'ar' ? 'الوصف' : 'Description'}</th><th className="px-3 py-2 text-end">{locale === 'ar' ? 'مدين' : 'Debit'}</th><th className="px-3 py-2 text-end">{locale === 'ar' ? 'دائن' : 'Credit'}</th></tr>
                </thead>
                <tbody className="divide-y">
                  {viewingLines.map(l => (
                    <tr key={l.id}>
                      <td className="px-3 py-2 text-xs">{l.account_code || '—'}</td>
                      <td className="px-3 py-2">{l.description_ar || '—'}</td>
                      <td className="px-3 py-2 text-end">{l.debit > 0 ? l.debit.toFixed(3) : ''}</td>
                      <td className="px-3 py-2 text-end">{l.credit > 0 ? l.credit.toFixed(3) : ''}</td>
                    </tr>
                  ))}
                  <tr className="bg-muted/30 font-bold"><td className="px-3 py-2" colSpan={2}>{locale === 'ar' ? 'الإجمالي' : 'Total'}</td><td className="px-3 py-2 text-end">{viewingEntry.total_debit.toFixed(3)}</td><td className="px-3 py-2 text-end">{viewingEntry.total_credit.toFixed(3)}</td></tr>
                </tbody>
              </table>
            </div>
            {viewingEntry.notes && <p className="text-xs text-muted-foreground">{viewingEntry.notes}</p>}
            <div className="flex justify-end gap-2 pt-2">
              <Button variant="secondary" onClick={() => setDialog(null)}>{t('action_cancel')}</Button>
            </div>
        </ModalOverlay>
      )}

      {/* Create form */}
      {dialog === 'create' && (
        <ModalOverlay closeLabel={locale === 'ar' ? 'إلغاء إنشاء السند' : 'Cancel voucher'} onClose={() => setDialog(null)} onSubmit={submitCreate} placement="start" contentClassName="my-8 w-full max-w-4xl rounded-2xl bg-card p-6 shadow-xl space-y-4">
            <h3 className="mb-2 font-semibold">{locale === 'ar' ? 'سند محاسبي يدوي جديد' : 'New manual accounting voucher'}</h3>
            <div className="grid gap-3 sm:grid-cols-4">
              <FormField>
                <FormLabel>{locale === 'ar' ? 'التاريخ' : 'Date'} *</FormLabel>
                <input type="date" value={formDate} onChange={e => setFormDate(e.target.value)} className={`${cell} w-full`} />
              </FormField>
              <FormField className="sm:col-span-2">
                <FormLabel>{locale === 'ar' ? 'البيان' : 'Description'}</FormLabel>
                <input value={formDesc} onChange={e => setFormDesc(e.target.value)} className={`${cell} w-full`} placeholder={locale === 'ar' ? 'مثال: تسوية مصاريف كهرباء' : 'e.g. electricity adjustment'} />
              </FormField>
              <FormField>
                <FormLabel>{locale === 'ar' ? 'العملة' : 'Currency'}</FormLabel>
                <select value={formCurrency} onChange={e => setFormCurrency(e.target.value as Currency)} className={`${cell} w-full`}>
                  {['OMR','EGP','USD','SAR','AED','EUR','GBP'].map(c => <option key={c} value={c}>{c}</option>)}
                </select>
              </FormField>
              <FormField>
                <FormLabel>{locale === 'ar' ? 'سعر الصرف' : 'FX'}</FormLabel>
                <input type="number" step="0.0001" min="0" value={formFx} onChange={e => setFormFx(e.target.value)} className={`${cell} w-full`} dir="ltr" />
              </FormField>
            </div>

            <div>
              <div className="mb-2 flex items-center justify-between">
                <FormLabel>{locale === 'ar' ? 'البنود (مدين / دائن)' : 'Lines (debit / credit)'}</FormLabel>
                <Button type="button" variant="secondary" size="sm" onClick={() => setFormLines(cur => [...cur, newLine()])}>
                  <Plus className="h-3.5 w-3.5" /> {locale === 'ar' ? 'سطر' : 'Line'}
                </Button>
              </div>
              <div className="space-y-2">
                {formLines.map(l => (
                  <div key={l.id} className="grid grid-cols-12 gap-2 items-start">
                    <input value={l.account_code} onChange={e => updateLine(l.id, { account_code: e.target.value })}
                      className={`${cell} col-span-12 sm:col-span-2`} placeholder={locale === 'ar' ? 'مرجع حساب اختياري' : 'Optional account ref'} dir="ltr" />
                    <input value={l.description_ar} onChange={e => updateLine(l.id, { description_ar: e.target.value })}
                      className={`${cell} col-span-12 sm:col-span-4`} placeholder={locale === 'ar' ? 'الوصف' : 'Description'} />
                    <select value={l.bank_account_id} onChange={e => updateLine(l.id, { bank_account_id: e.target.value })}
                      className={`${cell} col-span-6 sm:col-span-2`}>
                      <option value="">{locale === 'ar' ? 'بدون بنك' : 'no bank'}</option>
                      {activeBanks.map(a => <option key={a.id} value={a.id}>{a.currency} · {a.name_ar}</option>)}
                    </select>
                    <input type="number" min="0" step="0.001" value={l.debit} onChange={e => updateLine(l.id, { debit: e.target.value, credit: e.target.value ? '' : l.credit })}
                      className={`${cell} col-span-2 sm:col-span-1`} dir="ltr" placeholder={locale === 'ar' ? 'مدين' : 'Dr'} />
                    <input type="number" min="0" step="0.001" value={l.credit} onChange={e => updateLine(l.id, { credit: e.target.value, debit: e.target.value ? '' : l.debit })}
                      className={`${cell} col-span-2 sm:col-span-1`} dir="ltr" placeholder={locale === 'ar' ? 'دائن' : 'Cr'} />
                    <button type="button" onClick={() => removeLine(l.id)} disabled={formLines.length <= 2}
                      className="col-span-2 sm:col-span-1 flex h-10 items-center justify-center rounded-lg border border-border text-muted-foreground hover:text-danger disabled:opacity-50">
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </div>
                ))}
              </div>
            </div>

            <div className={`rounded-xl border p-3 text-sm ${balanced ? 'border-success/30 bg-success/5' : 'border-warning/30 bg-warning/5'}`}>
              <div className="flex justify-between"><span>{locale === 'ar' ? 'إجمالي مدين' : 'Total debit'}</span><span className="font-bold">{totalD.toFixed(3)} {formCurrency}</span></div>
              <div className="flex justify-between"><span>{locale === 'ar' ? 'إجمالي دائن' : 'Total credit'}</span><span className="font-bold">{totalC.toFixed(3)} {formCurrency}</span></div>
              <div className={`mt-1 flex justify-between border-t pt-1 font-bold ${balanced ? 'text-success' : 'text-warning'}`}>
                <span>{balanced ? (locale === 'ar' ? 'متوازن ✓' : 'Balanced ✓') : (locale === 'ar' ? 'الفرق' : 'Difference')}</span>
                <span>{balanced ? '—' : (totalD - totalC).toFixed(3)}</span>
              </div>
            </div>

            <FormField>
              <FormLabel>{locale === 'ar' ? 'ملاحظات' : 'Notes'}</FormLabel>
              <textarea rows={2} value={formNotes} onChange={e => setFormNotes(e.target.value)} className={`${cell} w-full`} />
            </FormField>

            {formError && <FormError>{formError}</FormError>}

            <div className="flex justify-end gap-2 pt-2">
              <Button type="button" variant="secondary" onClick={() => setDialog(null)} disabled={saving}>{t('action_cancel')}</Button>
              <Button type="submit" disabled={saving}>{saving ? (locale === 'ar' ? 'جارٍ الحفظ…' : 'Saving…') : (locale === 'ar' ? 'حفظ كمسودة' : 'Save draft')}</Button>
            </div>
        </ModalOverlay>
      )}
    </div>
  );
}

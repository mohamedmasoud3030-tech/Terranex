import { useEffect, useRef } from 'react';
import { ArrowDownCircle, ArrowUpCircle, FileText, Landmark, Users, X } from 'lucide-react';
import { Badge } from '../../components/ui/Badge';
import { Button } from '../../components/ui/Button';
import { MoneyValue } from '../../components/ui/MoneyValue';
import { formatDate } from '../../core/lib/date';
import { cn } from '../../core/lib/cn';
import { formatMoney } from '../../core/lib/format';
import { useI18n } from '../../core/i18n';
import type { AssetRowVM, ObligationRowVM, TransactionRowVM } from '../../core/types/ui';

interface RealEstateAssetDetail extends AssetRowVM {
  acquisition_date: string;
  valuation_date: string;
  notes: string;
  partners: { id: string; name_ar: string; equity_pct: number }[];
  transactions: TransactionRowVM[];
  obligations: ObligationRowVM[];
  documents: { id: string; title_ar: string; type_ar: string; date?: string }[];
}

interface AssetDetailDrawerProps {
  asset: RealEstateAssetDetail | null;
  onClose: () => void;
}

export function AssetDetailDrawer({ asset, onClose }: AssetDetailDrawerProps) {
  const { locale } = useI18n();
  const closeRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!asset) return;
    const timeout = window.setTimeout(() => closeRef.current?.focus(), 50);
    return () => window.clearTimeout(timeout);
  }, [asset]);

  useEffect(() => {
    if (!asset) return;
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') onClose();
    }
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [asset, onClose]);

  if (!asset) return null;

  const isProfit = asset.profit_loss_egp >= 0;
  const totalInvested = asset.acquisition_cost_egp + asset.development_cost_egp;

  return (
    <>
      <div className="fixed inset-0 z-40 bg-foreground/20 backdrop-blur-sm" onClick={onClose} aria-hidden="true" />
      <aside
        role="dialog"
        aria-modal="true"
        aria-label={`تفاصيل ${asset.name_ar}`}
        className="fixed inset-y-0 end-0 z-50 flex w-full max-w-2xl flex-col border-s border-border bg-card shadow-2xl"
      >
        <div className="flex items-start justify-between gap-4 border-b border-border p-5">
          <div>
            <p className="text-xs font-semibold text-muted-foreground">تفاصيل أصل استثماري</p>
            <h2 className="mt-1 text-xl font-bold leading-snug">{asset.name_ar}</h2>
            <p className="mt-1 text-sm text-muted-foreground">{asset.project_name_ar}</p>
          </div>
          <Button ref={closeRef} type="button" variant="ghost" size="icon" onClick={onClose} aria-label="إغلاق التفاصيل">
            <X className="h-5 w-5" aria-hidden="true" />
          </Button>
        </div>

        <div className="flex-1 overflow-y-auto p-5">
          <section className="grid gap-3 sm:grid-cols-2" aria-label="ملخص رأس المال">
            <MetricCard label="تكلفة الشراء" amount={asset.acquisition_cost_egp} />
            <MetricCard label="تكلفة التطوير" amount={asset.development_cost_egp} />
            <MetricCard label="إجمالي المستثمر" amount={totalInvested} />
            <div className={cn('rounded-2xl border p-4', isProfit ? 'border-success/30 bg-success/5' : 'border-danger/30 bg-danger/5')}>
              <p className="text-xs text-muted-foreground">الربح / الخسارة</p>
              <p className={cn('mt-2 text-xl font-black tabular-nums', isProfit ? 'text-success' : 'text-danger')}>
                {isProfit ? '+' : ''}{formatMoney(asset.profit_loss_egp, 'EGP', locale)}
              </p>
              <p className={cn('mt-1 text-xs font-bold', isProfit ? 'text-success' : 'text-danger')}>
                {isProfit ? '+' : ''}{asset.profit_loss_pct.toFixed(1)}% ROI
              </p>
            </div>
          </section>

          <section className="mt-6 rounded-2xl border border-border bg-muted/30 p-4" aria-label="ملخص الأصل">
            <div className="mb-3 flex items-center gap-2 text-sm font-bold">
              <Landmark className="h-4 w-4" aria-hidden="true" />
              بيانات الأصل
            </div>
            <div className="grid gap-3 text-sm sm:grid-cols-2">
              <InfoRow label="الموقع" value={asset.location ?? 'غير محدد'} />
              <InfoRow label="تاريخ الشراء" value={formatDate(asset.acquisition_date, locale)} />
              <InfoRow label="آخر تقييم" value={formatDate(asset.valuation_date, locale)} />
              <InfoRow label="عدد المستندات" value={`${asset.document_count}`} />
            </div>
            <p className="mt-4 text-sm leading-7 text-muted-foreground">{asset.notes}</p>
          </section>

          <section className="mt-6" aria-label="شركاء حقوق الملكية">
            <div className="mb-3 flex items-center gap-2 text-sm font-bold text-muted-foreground">
              <Users className="h-4 w-4" aria-hidden="true" />
              شركاء حقوق الملكية
            </div>
            <div className="space-y-2">
              {asset.partners.map((partner) => (
                <div key={partner.id} className="flex items-center justify-between rounded-xl border border-border px-4 py-3">
                  <div>
                    <p className="text-sm font-semibold">{partner.name_ar}</p>
                    <p className="mt-0.5 text-xs text-muted-foreground">نسبة الملكية: {partner.equity_pct}%</p>
                  </div>
                  <div className="text-end">
                    <p className="text-xs text-muted-foreground">حصة الربح الحالية</p>
                    <p className={cn('text-sm font-bold tabular-nums', isProfit ? 'text-success' : 'text-danger')}>
                      {formatMoney((asset.profit_loss_egp * partner.equity_pct) / 100, 'EGP', locale)}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </section>

          <section className="mt-6" aria-label="المعاملات المالية">
            <div className="mb-3 flex items-center gap-2 text-sm font-bold text-muted-foreground">
              <ArrowDownCircle className="h-4 w-4" aria-hidden="true" />
              المعاملات المالية
            </div>
            <div className="space-y-2">
              {asset.transactions.map((transaction) => {
                const isIncome = transaction.direction === 'income';
                return (
                  <div key={transaction.id} className="flex items-start justify-between gap-3 rounded-xl border border-border px-4 py-3">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        {isIncome ? <ArrowUpCircle className="h-4 w-4 shrink-0 text-success" aria-hidden="true" /> : <ArrowDownCircle className="h-4 w-4 shrink-0 text-danger" aria-hidden="true" />}
                        <p className="truncate text-sm font-semibold">{transaction.category_ar}</p>
                      </div>
                      <p className="mt-1 text-xs leading-5 text-muted-foreground">
                        {formatDate(transaction.date, locale)}
                        {transaction.counterparty_ar ? ` · ${transaction.counterparty_ar}` : ''}
                        {transaction.document_title ? ` · ${transaction.document_title}` : ''}
                      </p>
                    </div>
                    <p className={cn('shrink-0 text-sm font-bold tabular-nums', isIncome ? 'text-success' : 'text-danger')}>
                      {isIncome ? '+' : '-'}{formatMoney(transaction.amount_egp, 'EGP', locale)}
                    </p>
                  </div>
                );
              })}
            </div>
          </section>

          <section className="mt-6" aria-label="الالتزامات المفتوحة">
            <div className="mb-3 flex items-center gap-2 text-sm font-bold text-muted-foreground">
              <FileText className="h-4 w-4" aria-hidden="true" />
              الالتزامات
            </div>
            {asset.obligations.length === 0 ? (
              <div className="rounded-xl border border-dashed border-border p-4 text-sm text-muted-foreground">لا توجد التزامات مفتوحة على هذا الأصل.</div>
            ) : (
              <div className="space-y-2">
                {asset.obligations.map((obligation) => (
                  <div key={obligation.id} className="flex items-start justify-between gap-3 rounded-xl border border-border px-4 py-3">
                    <div>
                      <p className="text-sm font-semibold">{obligation.counterparty_ar}</p>
                      <p className="mt-1 text-xs text-muted-foreground">{formatDate(obligation.date, locale)} · {obligation.document_title ?? 'بدون مستند'}</p>
                    </div>
                    <div className="text-end">
                      <Badge tone={obligation.direction === 'receivable' ? 'positive' : 'warning'}>
                        {obligation.direction === 'receivable' ? 'ذمة مدينة' : 'ذمة دائنة'}
                      </Badge>
                      <p className="mt-1 text-sm font-bold tabular-nums">{formatMoney(obligation.amount_egp, 'EGP', locale)}</p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </section>

          <section className="mt-6" aria-label="المستندات الداعمة">
            <div className="mb-3 flex items-center gap-2 text-sm font-bold text-muted-foreground">
              <FileText className="h-4 w-4" aria-hidden="true" />
              المستندات الداعمة
            </div>
            <div className="grid gap-2 sm:grid-cols-2">
              {asset.documents.map((document) => (
                <div key={document.id} className="rounded-xl border border-border px-4 py-3">
                  <p className="text-sm font-semibold">{document.title_ar}</p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {document.type_ar}{document.date ? ` · ${formatDate(document.date, locale)}` : ''}
                  </p>
                </div>
              ))}
            </div>
          </section>
        </div>
      </aside>
    </>
  );
}

function MetricCard({ label, amount }: { label: string; amount: number }) {
  return (
    <div className="rounded-2xl border border-border bg-card p-4">
      <p className="text-xs text-muted-foreground">{label}</p>
      <div className="mt-2 font-bold tabular-nums">
        <MoneyValue amount={amount} currency="EGP" size="lg" />
      </div>
    </div>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs text-muted-foreground">{label}</p>
      <p className="mt-1 font-semibold">{value}</p>
    </div>
  );
}

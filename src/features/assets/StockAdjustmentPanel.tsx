import { useState, type FormEvent } from 'react';
import { todayIso } from '../../core/lib/dateUtils';
import { ClipboardList, Plus, X } from 'lucide-react';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { Button } from '../../components/ui/Button';
import { FormField, FormLabel, FormError, TextInput, SelectInput, TextArea } from '../../components/ui/FormControls';
import { Badge } from '../../components/ui/Badge';
import { formatEgp } from '../../core/lib/profitability';
import { useStockAdjustments, computeAssetLiveQuantity, useOperationalEvents } from './hooks_adj';
import type { Asset, AdjustmentReason } from '../../core/types/domain';
import type { StockAdjustmentInput } from '../events/storage';

const REASON_LABELS: Record<AdjustmentReason, string> = {
  opening_balance: 'رصيد افتتاحي',
  data_correction: 'تصحيح بيانات',
  external_audit: 'مراجعة خارجية',
  reconciliation: 'تسوية',
  other: 'أخرى',
};

const REASONS = Object.keys(REASON_LABELS) as AdjustmentReason[];


interface StockAdjustmentPanelProps {
  asset: Asset;
}

export function StockAdjustmentPanel({ asset }: StockAdjustmentPanelProps) {
  const { adjustments, createAdjustment } = useStockAdjustments(asset.id);
  const { events } = useOperationalEvents(asset.id);
  const liveBalance = computeAssetLiveQuantity(asset.quantity ?? 0, events, adjustments);

  const [open, setOpen] = useState(false);
  const [qtyBefore, setQtyBefore] = useState('');
  const [qtyAfter, setQtyAfter] = useState('');
  const [valBefore, setValBefore] = useState('');
  const [valAfter, setValAfter] = useState('');
  const [reason, setReason] = useState<AdjustmentReason>('data_correction');
  const [adjDate, setAdjDate] = useState(todayIso());
  const [notes, setNotes] = useState('');
  const [error, setError] = useState('');

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    const qb = Number(qtyBefore);
    const qa = Number(qtyAfter);
    const vb = Number(valBefore);
    const va = Number(valAfter);
    if (!Number.isFinite(qb) || !Number.isFinite(qa) || !Number.isFinite(vb) || !Number.isFinite(va)) {
      setError('أدخل أرقاماً صحيحة لكل الحقول.');
      return;
    }
    if (!adjDate) {
      setError('التاريخ مطلوب.');
      return;
    }
    const input: StockAdjustmentInput = {
      asset_id: asset.id,
      project_id: asset.project_id,
      adjustment_date: adjDate,
      quantity_before: qb,
      quantity_after: qa,
      value_egp_before: vb,
      value_egp_after: va,
      reason,
      notes: notes.trim() || undefined,
    };
    createAdjustment(input);
    setOpen(false);
    setQtyBefore('');
    setQtyAfter('');
    setValBefore('');
    setValAfter('');
    setNotes('');
    setError('');
  }

  return (
    <div className="mt-4 space-y-3">
      {/* Live balance */}
      <div className="flex items-center justify-between rounded-xl border border-border bg-muted/30 px-4 py-3">
        <span className="text-sm text-muted-foreground">الرصيد الحي</span>
        <span className="font-bold text-foreground">
          {liveBalance.quantity} {asset.unit ?? ''}
        </span>
      </div>

      {/* Adjustments list */}
      {adjustments.length > 0 && (
        <Card>
          <CardHeader>
            <div className="flex items-center gap-2">
              <ClipboardList className="h-4 w-4 text-muted-foreground" />
              <span className="text-sm font-semibold">سجل التسويات ({adjustments.length})</span>
            </div>
          </CardHeader>
          <CardContent className="p-0">
            <div className="divide-y divide-border">
              {adjustments.map((adj) => (
                <div key={adj.id} className="flex items-start justify-between gap-3 px-4 py-3 text-sm">
                  <div className="space-y-0.5">
                    <div className="flex items-center gap-2">
                      <Badge tone="neutral">{REASON_LABELS[adj.reason]}</Badge>
                      <span className="text-xs text-muted-foreground">{adj.adjustment_date}</span>
                    </div>
                    <p className="text-xs text-muted-foreground">
                      الكمية: {adj.quantity_before} → <span className="font-medium text-foreground">{adj.quantity_after}</span>
                      {' '}| القيمة: {formatEgp(adj.value_egp_before, true)} → <span className="font-medium text-foreground">{formatEgp(adj.value_egp_after, true)} EGP</span>
                    </p>
                    {adj.notes && <p className="text-xs text-muted-foreground">{adj.notes}</p>}
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Form toggle */}
      {open ? (
        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <span className="text-sm font-semibold">تسوية جديدة</span>
              <button onClick={() => setOpen(false)} className="text-muted-foreground hover:text-foreground">
                <X className="h-4 w-4" />
              </button>
            </div>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleSubmit} className="space-y-3">
              <div className="grid grid-cols-2 gap-3">
                <FormField>
                  <FormLabel>الكمية قبل</FormLabel>
                  <TextInput type="number" value={qtyBefore} onChange={e => setQtyBefore(e.target.value)} placeholder="0" />
                </FormField>
                <FormField>
                  <FormLabel>الكمية بعد</FormLabel>
                  <TextInput type="number" value={qtyAfter} onChange={e => setQtyAfter(e.target.value)} placeholder="0" />
                </FormField>
                <FormField>
                  <FormLabel>القيمة قبل (EGP)</FormLabel>
                  <TextInput type="number" value={valBefore} onChange={e => setValBefore(e.target.value)} placeholder="0" />
                </FormField>
                <FormField>
                  <FormLabel>القيمة بعد (EGP)</FormLabel>
                  <TextInput type="number" value={valAfter} onChange={e => setValAfter(e.target.value)} placeholder="0" />
                </FormField>
              </div>
              <FormField>
                <FormLabel>السبب</FormLabel>
                <SelectInput value={reason} onChange={e => setReason(e.target.value as AdjustmentReason)}>
                  {REASONS.map(r => <option key={r} value={r}>{REASON_LABELS[r]}</option>)}
                </SelectInput>
              </FormField>
              <FormField>
                <FormLabel>التاريخ</FormLabel>
                <TextInput type="date" value={adjDate} onChange={e => setAdjDate(e.target.value)} />
              </FormField>
              <FormField>
                <FormLabel>ملاحظات (اختياري)</FormLabel>
                <TextArea value={notes} onChange={e => setNotes(e.target.value)} rows={2} />
              </FormField>
              {error && <FormError>{error}</FormError>}
              <div className="flex gap-2">
                <Button type="submit" variant="primary" size="sm" className="flex-1">تسجيل التسوية</Button>
                <Button type="button" variant="ghost" size="sm" onClick={() => setOpen(false)}>إلغاء</Button>
              </div>
            </form>
          </CardContent>
        </Card>
      ) : (
        <Button variant="secondary" size="sm" className="w-full gap-1.5" onClick={() => setOpen(true)}>
          <Plus className="h-4 w-4" /> تسوية كمية / قيمة
        </Button>
      )}
    </div>
  );
}

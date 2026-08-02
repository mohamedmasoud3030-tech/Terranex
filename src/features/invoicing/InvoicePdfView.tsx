import { useEffect, useState } from 'react';
import { Document, Page, Text, View, StyleSheet, PDFViewer } from '@react-pdf/renderer';
import { listInvoiceLines } from './storage';
import type { SalesInvoice, SalesInvoiceLine } from '../../core/types/domain';
import { requireClient } from '../../core/storage/supabaseClientRegistry';

const styles = StyleSheet.create({
  page: { padding: 40, fontFamily: 'Helvetica', fontSize: 10 },
  header: { flexDirection: 'row', justifyContent: 'space-between', marginBottom: 20 },
  title: { fontSize: 22, fontWeight: 'bold', marginBottom: 4 },
  meta: { fontSize: 9, color: '#555', marginBottom: 2 },
  table: { display: 'flex', width: 'auto', borderWidth: 1, borderColor: '#ddd', marginTop: 12 },
  row: { flexDirection: 'row', borderBottomWidth: 1, borderBottomColor: '#ddd' },
  cell: { padding: 6, flex: 1 },
  cellQty: { padding: 6, width: 40 },
  cellPrice: { padding: 6, width: 70, textAlign: 'right' },
  cellTotal: { padding: 6, width: 80, textAlign: 'right' },
  totals: { marginTop: 12, alignSelf: 'flex-end', width: 200 },
  totalRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 2 },
});

function InvoiceDoc({ invoice, lines }: { invoice: SalesInvoice; lines: SalesInvoiceLine[] }) {
  return (
    <Document>
      <Page size="A4" style={styles.page}>
        <View style={styles.header}>
          <View>
            <Text style={styles.title}>فاتورة مبيعات / Sales Invoice</Text>
            <Text style={styles.meta}>{invoice.invoice_number}</Text>
            <Text style={styles.meta}>التاريخ: {invoice.issue_date}</Text>
            {invoice.due_date && <Text style={styles.meta}>تاريخ الاستحقاق: {invoice.due_date}</Text>}
          </View>
          <View>
            <Text style={styles.meta}>الحالة: {invoice.status}</Text>
            <Text style={styles.meta}>العملة: {invoice.currency}</Text>
          </View>
        </View>

        <View style={styles.table}>
          <View style={[styles.row, { backgroundColor: '#f5f5f5', fontWeight: 'bold' }]}>
            <Text style={styles.cellQty}>#</Text>
            <Text style={styles.cell}>البند / Item</Text>
            <Text style={styles.cellQty}>الكمية</Text>
            <Text style={styles.cellPrice}>السعر</Text>
            <Text style={styles.cellTotal}>الإجمالي</Text>
          </View>
          {lines.map((l) => (
            <View key={l.id} style={styles.row}>
              <Text style={styles.cellQty}>{l.line_no}</Text>
              <Text style={styles.cell}>{l.description_ar || l.description_en || '—'}</Text>
              <Text style={styles.cellQty}>{l.quantity}</Text>
              <Text style={styles.cellPrice}>{l.unit_price.toFixed(3)}</Text>
              <Text style={styles.cellTotal}>{l.line_total.toFixed(3)}</Text>
            </View>
          ))}
        </View>

        <View style={styles.totals}>
          <View style={styles.totalRow}><Text>المجموع الفرعي</Text><Text>{invoice.subtotal.toFixed(3)}</Text></View>
          <View style={styles.totalRow}><Text>ضريبة {invoice.vat_rate}%</Text><Text>{invoice.vat_amount.toFixed(3)}</Text></View>
          <View style={[styles.totalRow, { fontWeight: 'bold', fontSize: 12, borderTopWidth: 1, paddingTop: 4 }]}>
            <Text>الإجمالي</Text><Text>{invoice.total.toFixed(3)} {invoice.currency}</Text>
          </View>
        </View>

        {invoice.notes && (
          <View style={{ marginTop: 20, fontSize: 9, color: '#555' }}>
            <Text>{invoice.notes}</Text>
          </View>
        )}
      </Page>
    </Document>
  );
}

export function InvoicePdfView({ invoiceId }: { invoiceId: string }) {
  const [invoice, setInvoice] = useState<SalesInvoice | null>(null);
  const [lines, setLines] = useState<SalesInvoiceLine[]>([]);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const supabase = requireClient();
        const { data, error } = await supabase.from('sales_invoices').select('*').eq('id', invoiceId).single();
        if (error) throw error;
        const ls = await listInvoiceLines(invoiceId);
        if (cancelled) return;
        setInvoice(data as SalesInvoice);
        setLines(ls);
      } catch (e) {
        if (!cancelled) setErr(e instanceof Error ? e.message : String(e));
      }
    })();
    return () => { cancelled = true; };
  }, [invoiceId]);

  if (err) return <p className="text-sm text-danger">{err}</p>;
  if (!invoice) return <p className="text-sm text-muted-foreground">...</p>;

  return (
    <PDFViewer width="100%" height={600} className="rounded-xl border">
      <InvoiceDoc invoice={invoice} lines={lines} />
    </PDFViewer>
  );
}

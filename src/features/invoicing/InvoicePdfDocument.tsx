import { useEffect, useState } from 'react';
import { Document, Page, PDFViewer, StyleSheet, Text, View } from '@react-pdf/renderer';
import { requireClient } from '../../core/storage/supabaseClientRegistry';

type PdfInvoice = {
  invoice_number: string;
  vendor_invoice_number?: string;
  issue_date: string;
  due_date?: string;
  status: string;
  currency: string;
  subtotal: number;
  vat_rate: number;
  vat_amount: number;
  total: number;
  amount_paid: number;
  notes?: string;
};

type PdfLine = {
  id: string;
  line_no: number;
  description_ar?: string;
  description_en?: string;
  quantity: number;
  unit_price: number;
  line_total: number;
};

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
  totals: { marginTop: 12, alignSelf: 'flex-end', width: 220 },
  totalRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 2 },
});

function InvoiceDocument({ kind, invoice, lines }: Readonly<{ kind: 'sales' | 'purchase'; invoice: PdfInvoice; lines: PdfLine[] }>) {
  const outstanding = Math.max(0, invoice.total - invoice.amount_paid);
  return (
    <Document>
      <Page size="A4" style={styles.page}>
        <View style={styles.header}>
          <View>
            <Text style={styles.title}>{kind === 'purchase' ? 'فاتورة مشتريات / Purchase Bill' : 'فاتورة مبيعات / Sales Invoice'}</Text>
            <Text style={styles.meta}>{invoice.invoice_number}</Text>
            {invoice.vendor_invoice_number && <Text style={styles.meta}>رقم فاتورة المورد: {invoice.vendor_invoice_number}</Text>}
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
            <Text style={styles.cellQty}>#</Text><Text style={styles.cell}>البند / Item</Text>
            <Text style={styles.cellQty}>الكمية</Text><Text style={styles.cellPrice}>السعر</Text><Text style={styles.cellTotal}>الإجمالي</Text>
          </View>
          {lines.map(line => (
            <View key={line.id} style={styles.row}>
              <Text style={styles.cellQty}>{line.line_no}</Text>
              <Text style={styles.cell}>{line.description_ar || line.description_en || '—'}</Text>
              <Text style={styles.cellQty}>{line.quantity}</Text>
              <Text style={styles.cellPrice}>{line.unit_price.toFixed(3)}</Text>
              <Text style={styles.cellTotal}>{line.line_total.toFixed(3)}</Text>
            </View>
          ))}
        </View>
        <View style={styles.totals}>
          <View style={styles.totalRow}><Text>المجموع الفرعي</Text><Text>{invoice.subtotal.toFixed(3)}</Text></View>
          <View style={styles.totalRow}><Text>ضريبة {invoice.vat_rate}%</Text><Text>{invoice.vat_amount.toFixed(3)}</Text></View>
          <View style={[styles.totalRow, { fontWeight: 'bold', fontSize: 12, borderTopWidth: 1, paddingTop: 4 }]}>
            <Text>الإجمالي</Text><Text>{invoice.total.toFixed(3)} {invoice.currency}</Text>
          </View>
          {invoice.amount_paid > 0 && <View style={styles.totalRow}><Text>مدفوع</Text><Text>{invoice.amount_paid.toFixed(3)}</Text></View>}
          {outstanding > 0 && <View style={[styles.totalRow, { color: '#b45309' }]}><Text>مستحق</Text><Text>{outstanding.toFixed(3)}</Text></View>}
        </View>
        {invoice.notes && <View style={{ marginTop: 20, fontSize: 9, color: '#555' }}><Text>{invoice.notes}</Text></View>}
      </Page>
    </Document>
  );
}

export function InvoicePdfViewBase({ invoiceId, table, kind, listLines }: Readonly<{
  invoiceId: string;
  table: 'sales_invoices' | 'purchase_invoices';
  kind: 'sales' | 'purchase';
  listLines: (id: string) => Promise<PdfLine[]>;
}>) {
  const [invoice, setInvoice] = useState<PdfInvoice | null>(null);
  const [lines, setLines] = useState<PdfLine[]>([]);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      try {
        const { data, error } = await requireClient().from(table).select('*').eq('id', invoiceId).single();
        if (error) throw error;
        const loadedLines = await listLines(invoiceId);
        if (!cancelled) { setInvoice(data as PdfInvoice); setLines(loadedLines); }
      } catch (error) {
        if (!cancelled) setErrorMessage(error instanceof Error ? error.message : String(error));
      }
    })();
    return () => { cancelled = true; };
  }, [invoiceId, listLines, table]);
  if (errorMessage) return <p className="text-sm text-danger">{errorMessage}</p>;
  if (!invoice) return <p className="text-sm text-muted-foreground">...</p>;
  return <PDFViewer width="100%" height={600} className="rounded-xl border"><InvoiceDocument kind={kind} invoice={invoice} lines={lines} /></PDFViewer>;
}

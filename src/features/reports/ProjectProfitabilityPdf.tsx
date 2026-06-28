import React from 'react';
import { Document, Page, Text, View, StyleSheet, Font } from '@react-pdf/renderer';
import type { ProjectProfitability, Project, Transaction, Obligation } from '../../core/types/domain';
import { formatEgp } from '../../core/lib/profitability';

// Use built-in Helvetica — Arabic will show as boxes in PDF without Arabic font,
// so we provide both AR and EN labels and keep numbers LTR.
// For production: register Noto Kufi Arabic via Font.register({ family: 'NotoKufi', src: '/fonts/NotoKufiArabic-Regular.ttf' })

const styles = StyleSheet.create({
  page: {
    padding: 32,
    fontSize: 11,
    fontFamily: 'Helvetica',
    backgroundColor: '#ffffff',
    color: '#0f172a',
  },
  header: {
    marginBottom: 16,
    borderBottomWidth: 2,
    borderBottomColor: '#1e3a8a',
    paddingBottom: 10,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-end',
  },
  brand: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#1e3a8a',
  },
  brandSub: {
    fontSize: 9,
    color: '#64748b',
    marginTop: 2,
  },
  metaRight: {
    textAlign: 'right',
    fontSize: 9,
    color: '#475569',
  },
  title: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 4,
    marginTop: 8,
  },
  subTitle: {
    fontSize: 10,
    color: '#475569',
    marginBottom: 12,
  },
  kpiGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    marginBottom: 14,
    gap: 8,
  },
  kpiBox: {
    width: '23%',
    borderWidth: 1,
    borderColor: '#e2e8f0',
    borderRadius: 6,
    padding: 8,
    backgroundColor: '#f8fafc',
  },
  kpiLabel: {
    fontSize: 8,
    color: '#64748b',
    marginBottom: 4,
  },
  kpiValue: {
    fontSize: 13,
    fontWeight: 'bold',
  },
  sectionTitle: {
    fontSize: 12,
    fontWeight: 'bold',
    marginTop: 14,
    marginBottom: 6,
    backgroundColor: '#f1f5f9',
    padding: 6,
  },
  tableHeader: {
    flexDirection: 'row',
    borderBottomWidth: 1,
    borderBottomColor: '#cbd5e1',
    paddingBottom: 4,
    marginBottom: 4,
  },
  th: {
    fontSize: 9,
    fontWeight: 'bold',
    color: '#334155',
    flex: 1,
  },
  tr: {
    flexDirection: 'row',
    paddingVertical: 3,
    borderBottomWidth: 0.5,
    borderBottomColor: '#f1f5f9',
  },
  td: {
    fontSize: 9,
    flex: 1,
    color: '#0f172a',
  },
  tdRight: {
    fontSize: 9,
    flex: 1,
    textAlign: 'right',
    color: '#0f172a',
  },
  footer: {
    position: 'absolute',
    bottom: 24,
    left: 32,
    right: 32,
    fontSize: 8,
    color: '#94a3b8',
    textAlign: 'center',
    borderTopWidth: 1,
    borderTopColor: '#e2e8f0',
    paddingTop: 6,
  },
  positive: { color: '#16a34a' },
  negative: { color: '#dc2626' },
  muted: { color: '#64748b' },
  partnerRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 3,
  },
});

interface Props {
  project: Project;
  profitability: ProjectProfitability;
  transactions: Transaction[];
  obligations: Obligation[];
  generatedAt?: string;
  generatedBy?: string;
}

export function ProjectProfitabilityPdfDocument({
  project,
  profitability,
  transactions,
  obligations,
  generatedAt = new Date().toISOString().slice(0, 19).replace('T', ' '),
  generatedBy = 'Terranex v0.4.0',
}: Props) {
  const txs = transactions
    .filter(t => t.project_id === project.id)
    .sort((a,b) => b.transaction_date.localeCompare(a.transaction_date))
    .slice(0, 40); // limit for PDF length

  const openObls = obligations
    .filter(o => o.project_id === project.id && o.status !== 'settled' && o.status !== 'written_off')
    .slice(0, 20);

  return (
    <Document
      title={`Terranex P&L - ${project.name_en || project.name_ar}`}
      author="Terranex Investment Operating System"
      subject={`Project Profitability Report — ${project.id}`}
      creator="Terranex PDF Engine"
      producer="Terranex v0.4.0 / @react-pdf/renderer"
      language="ar"
    >
      <Page size="A4" style={styles.page}>
        {/* Header */}
        <View style={styles.header}>
          <View>
            <Text style={styles.brand}>Terranex</Text>
            <Text style={styles.brandSub}>Investment Operating System — نظام التشغيل الاستثماري</Text>
            <Text style={styles.brandSub}>Real Estate • Agriculture • Livestock</Text>
          </View>
          <View style={styles.metaRight}>
            <Text>Project P&L Report</Text>
            <Text>تقرير ربحية المشروع</Text>
            <Text>Generated: {generatedAt} UTC</Text>
            <Text>{generatedBy}</Text>
          </View>
        </View>

        {/* Project Title */}
        <Text style={styles.title}>
          {project.name_en || project.name_ar} — {project.name_ar}
        </Text>
        <Text style={styles.subTitle}>
          Sector: {project.sector_id} • Status: {project.status} • Period: {profitability.period.from} → {profitability.period.to} • Base: {project.base_currency} — Reporting: EGP
        </Text>

        {/* KPI Grid */}
        <View style={styles.kpiGrid}>
          <View style={styles.kpiBox}>
            <Text style={styles.kpiLabel}>Total Income / إجمالي الإيرادات</Text>
            <Text style={[styles.kpiValue, styles.positive]}>{formatEgp(profitability.total_income_egp)} EGP</Text>
          </View>
          <View style={styles.kpiBox}>
            <Text style={styles.kpiLabel}>Total Expense / إجمالي المصروفات</Text>
            <Text style={[styles.kpiValue, styles.negative]}>{formatEgp(profitability.total_expense_egp)} EGP</Text>
          </View>
          <View style={styles.kpiBox}>
            <Text style={styles.kpiLabel}>Gross Profit / إجمالي الربح</Text>
            <Text style={[styles.kpiValue, profitability.gross_profit_egp >= 0 ? styles.positive : styles.negative]}>
              {formatEgp(profitability.gross_profit_egp)} EGP
            </Text>
          </View>
          <View style={styles.kpiBox}>
            <Text style={styles.kpiLabel}>Cash Exposure / التعرض النقدي</Text>
            <Text style={[styles.kpiValue, profitability.cash_exposure_egp >= 0 ? styles.positive : styles.negative]}>
              {formatEgp(profitability.cash_exposure_egp)} EGP
            </Text>
          </View>
        </View>

        {/* Obligations summary */}
        <View style={{ flexDirection: 'row', gap: 24, marginBottom: 8 }}>
          <Text style={[styles.muted, { fontSize: 9 }]}>
            Open Receivables: {formatEgp(profitability.open_receivables_egp)} EGP  •  Open Payables: {formatEgp(profitability.open_payables_egp)} EGP
          </Text>
        </View>

        {/* Partner splits */}
        {profitability.partner_splits.length > 0 && (
          <>
            <Text style={styles.sectionTitle}>Partner Profit Split / توزيع أرباح الشركاء</Text>
            <View style={styles.tableHeader}>
              <Text style={[styles.th, { flex: 2 }]}>Partner / الشريك</Text>
              <Text style={styles.th}>Equity %</Text>
              <Text style={[styles.th, { textAlign: 'right' }]}>Share EGP</Text>
            </View>
            {profitability.partner_splits.map(ps => (
              <View key={ps.partner_id} style={styles.partnerRow}>
                <Text style={[styles.td, { flex: 2 }]}>{ps.partner_name_ar} — {ps.partner_id}</Text>
                <Text style={styles.td}>{ps.equity_pct.toFixed(2)}%</Text>
                <Text style={[styles.tdRight, ps.share_egp >= 0 ? styles.positive : styles.negative]}>
                  {formatEgp(ps.share_egp)} EGP
                </Text>
              </View>
            ))}
          </>
        )}

        {/* Transactions */}
        <Text style={styles.sectionTitle}>
          Recent Transactions / آخر المعاملات — Top {txs.length}
        </Text>
        <View style={styles.tableHeader}>
          <Text style={[styles.th, { flex: 1.1 }]}>Date</Text>
          <Text style={[styles.th, { flex: 1 }]}>Dir</Text>
          <Text style={[styles.th, { flex: 2 }]}>Category</Text>
          <Text style={[styles.th, { textAlign: 'right' }]}>Amount EGP</Text>
        </View>
        {txs.map(tx => (
          <View key={tx.id} style={styles.tr}>
            <Text style={[styles.td, { flex: 1.1 }]}>{tx.transaction_date}</Text>
            <Text style={[styles.td, tx.direction === 'income' ? styles.positive : styles.negative, { flex: 1 }]}>
              {tx.direction}
            </Text>
            <Text style={[styles.td, { flex: 2 }]}>{tx.category}</Text>
            <Text style={[styles.tdRight, tx.direction === 'income' ? styles.positive : styles.negative]}>
              {tx.direction === 'income' ? '+' : '−'}{formatEgp(tx.amount_egp)}
            </Text>
          </View>
        ))}
        {txs.length === 0 && (
          <Text style={[styles.muted, { fontSize: 9, textAlign: 'center', marginTop: 8 }]}>
            No transactions recorded yet — لا توجد معاملات مسجلة بعد
          </Text>
        )}

        {/* Open obligations */}
        {openObls.length > 0 && (
          <>
            <Text style={styles.sectionTitle}>Open Obligations / التزامات مفتوحة</Text>
            <View style={styles.tableHeader}>
              <Text style={styles.th}>Partner</Text>
              <Text style={styles.th}>Dir</Text>
              <Text style={styles.th}>Due</Text>
              <Text style={[styles.th, { textAlign: 'right' }]}>Open EGP</Text>
            </View>
            {openObls.map(o => {
              const openBal = Math.max(0, o.amount_egp - o.amount_settled_egp);
              return (
                <View key={o.id} style={styles.tr}>
                  <Text style={styles.td}>{o.partner_id}</Text>
                  <Text style={[styles.td, o.direction === 'receivable' ? styles.positive : styles.negative]}>
                    {o.direction}
                  </Text>
                  <Text style={styles.td}>{o.due_date ?? '—'}</Text>
                  <Text style={styles.tdRight}>{formatEgp(openBal)}</Text>
                </View>
              );
            })}
          </>
        )}

        {/* Audit footer */}
        <Text style={styles.footer} fixed>
          Terranex — Investment Operating System — {project.id} • Profit = Σ Income − Σ Expense — All figures in EGP — {generatedAt}
          {'\n'}
          كل رقم مالي مُتتبع لمصدره: معاملة + مستند + شريك — Audit trail preserved.
        </Text>
      </Page>
    </Document>
  );
}

// Helper to trigger browser download
export async function downloadProjectPdf(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

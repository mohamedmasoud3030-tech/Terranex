import React from 'react';
import { Document, Page, Text, View, StyleSheet } from '@react-pdf/renderer';
import type { ProjectProfitability, Transaction, Obligation, SectorId } from '../../core/types/domain';
import type { GlobalSummary, SectorSummary } from '../../core/lib/profitability';
import { formatEgp } from '../../core/lib/profitability';

const SECTOR_EN: Record<SectorId, string> = {
  'real-estate': 'Real Estate / العقاري',
  agriculture:   'Agriculture / الزراعي',
  livestock:     'Livestock / الحيواني',
};

const styles = StyleSheet.create({
  page: { padding: 32, fontSize: 10, fontFamily: 'Helvetica', backgroundColor: '#fff', color: '#0f172a' },
  header: { marginBottom: 14, borderBottomWidth: 2, borderBottomColor: '#1e3a8a', paddingBottom: 10, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-end' },
  brand: { fontSize: 20, fontWeight: 'bold', color: '#1e3a8a' },
  brandSub: { fontSize: 8, color: '#64748b', marginTop: 2 },
  metaRight: { textAlign: 'right', fontSize: 8, color: '#475569' },
  title: { fontSize: 15, fontWeight: 'bold', marginBottom: 2, marginTop: 6 },
  subTitle: { fontSize: 9, color: '#475569', marginBottom: 10 },
  kpiGrid: { flexDirection: 'row', gap: 8, marginBottom: 12 },
  kpiBox: { flex: 1, borderWidth: 1, borderColor: '#e2e8f0', borderRadius: 6, padding: 8, backgroundColor: '#f8fafc' },
  kpiLabel: { fontSize: 7.5, color: '#64748b', marginBottom: 3 },
  kpiValue: { fontSize: 13, fontWeight: 'bold' },
  sectionTitle: { fontSize: 11, fontWeight: 'bold', marginTop: 12, marginBottom: 5, backgroundColor: '#f1f5f9', padding: 5 },
  tableHeader: { flexDirection: 'row', borderBottomWidth: 1, borderBottomColor: '#cbd5e1', paddingBottom: 3, marginBottom: 3 },
  th: { fontSize: 8, fontWeight: 'bold', color: '#334155', flex: 1 },
  tr: { flexDirection: 'row', paddingVertical: 2.5, borderBottomWidth: 0.5, borderBottomColor: '#f1f5f9' },
  td: { fontSize: 8.5, flex: 1, color: '#0f172a' },
  tdR: { fontSize: 8.5, flex: 1, textAlign: 'right', color: '#0f172a' },
  footer: { position: 'absolute', bottom: 22, left: 32, right: 32, fontSize: 7.5, color: '#94a3b8', textAlign: 'center', borderTopWidth: 1, borderTopColor: '#e2e8f0', paddingTop: 5 },
  positive: { color: '#16a34a' },
  negative: { color: '#dc2626' },
  muted: { color: '#64748b' },
  sectorRow: { flexDirection: 'row', paddingVertical: 4, borderBottomWidth: 0.5, borderBottomColor: '#f1f5f9' },
});

interface Props {
  global: GlobalSummary;
  projectProfits: ProjectProfitability[];
  transactions: Transaction[];
  obligations: Obligation[];
  generatedAt?: string;
  generatedBy?: string;
}

export function GlobalProfitabilityPdfDocument({
  global,
  projectProfits,
  transactions,
  obligations,
  generatedAt = new Date().toISOString().replace('T', ' ').slice(0, 19),
  generatedBy = 'Terranex v0.3.0',
}: Props) {
  const isProfit = global.gross_profit_egp >= 0;

  // Top 30 recent transactions across all projects
  const recentTx = [...transactions]
    .sort((a, b) => b.transaction_date.localeCompare(a.transaction_date))
    .slice(0, 30);

  // Open obligations across all projects
  const openObls = obligations
    .filter(o => o.status !== 'settled' && o.status !== 'written_off')
    .slice(0, 25);

  return (
    <Document
      title="Terranex — Global P&L Report"
      author="Terranex Investment Operating System"
      subject="Global Profitability Report — All Sectors"
      creator="Terranex PDF Engine"
      producer={`Terranex v0.3.0 / @react-pdf/renderer — ${generatedAt}`}
      language="en"
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
            <Text>Global P&L Report / تقرير الربحية الإجمالي</Text>
            <Text>All Sectors — All Projects</Text>
            <Text>Generated: {generatedAt} UTC</Text>
            <Text>{generatedBy}</Text>
          </View>
        </View>

        {/* Title */}
        <Text style={styles.title}>Global Profitability — تقرير الربحية الشاملة</Text>
        <Text style={styles.subTitle}>
          Projects: {projectProfits.length} • Sectors: {Object.values(global.by_sector).filter((s: SectorSummary) => s.project_count > 0).length} active • Reporting Currency: EGP
        </Text>

        {/* KPI Grid */}
        <View style={styles.kpiGrid}>
          <View style={styles.kpiBox}>
            <Text style={styles.kpiLabel}>Total Income / إجمالي الإيرادات</Text>
            <Text style={[styles.kpiValue, styles.positive]}>{formatEgp(global.total_income_egp)} EGP</Text>
          </View>
          <View style={styles.kpiBox}>
            <Text style={styles.kpiLabel}>Total Expense / إجمالي المصروفات</Text>
            <Text style={[styles.kpiValue, styles.negative]}>{formatEgp(global.total_expense_egp)} EGP</Text>
          </View>
          <View style={styles.kpiBox}>
            <Text style={styles.kpiLabel}>Gross Profit / إجمالي الربح</Text>
            <Text style={[styles.kpiValue, isProfit ? styles.positive : styles.negative]}>
              {formatEgp(global.gross_profit_egp)} EGP
            </Text>
          </View>
          <View style={styles.kpiBox}>
            <Text style={styles.kpiLabel}>Profit Margin / هامش الربح</Text>
            <Text style={[styles.kpiValue, isProfit ? styles.positive : styles.negative]}>
              {global.margin_pct.toFixed(1)}%
            </Text>
          </View>
        </View>

        {/* By Sector */}
        <Text style={styles.sectionTitle}>By Sector / بالقطاع</Text>
        <View style={styles.tableHeader}>
          <Text style={[styles.th, { flex: 2 }]}>Sector</Text>
          <Text style={styles.th}>Projects</Text>
          <Text style={styles.th}>Income EGP</Text>
          <Text style={styles.th}>Expense EGP</Text>
          <Text style={[styles.th, { textAlign: 'right' }]}>Profit EGP</Text>
        </View>
        {(Object.keys(global.by_sector) as SectorId[]).map(sid => {
          const s = global.by_sector[sid] as SectorSummary;
          const pos = s.gross_profit_egp >= 0;
          return (
            <View key={sid} style={styles.sectorRow}>
              <Text style={[styles.td, { flex: 2 }]}>{SECTOR_EN[sid]}</Text>
              <Text style={styles.td}>{s.project_count}</Text>
              <Text style={[styles.td, styles.positive]}>{formatEgp(s.total_income_egp)}</Text>
              <Text style={[styles.td, styles.negative]}>{formatEgp(s.total_expense_egp)}</Text>
              <Text style={[styles.tdR, pos ? styles.positive : styles.negative]}>
                {pos ? '+' : ''}{formatEgp(s.gross_profit_egp)}
              </Text>
            </View>
          );
        })}

        {/* By Project */}
        <Text style={styles.sectionTitle}>By Project / بالمشروع ({projectProfits.length})</Text>
        <View style={styles.tableHeader}>
          <Text style={[styles.th, { flex: 3 }]}>Project</Text>
          <Text style={styles.th}>Sector</Text>
          <Text style={styles.th}>Income</Text>
          <Text style={styles.th}>Expense</Text>
          <Text style={[styles.th, { textAlign: 'right' }]}>Profit EGP</Text>
        </View>
        {projectProfits.map(pp => {
          const pos = pp.gross_profit_egp >= 0;
          return (
            <View key={pp.project_id} style={styles.tr}>
              <Text style={[styles.td, { flex: 3 }]}>{pp.project_name_en || pp.project_name_ar}</Text>
              <Text style={styles.td}>{pp.sector_id}</Text>
              <Text style={[styles.td, styles.positive]}>{formatEgp(pp.total_income_egp)}</Text>
              <Text style={[styles.td, styles.negative]}>{formatEgp(pp.total_expense_egp)}</Text>
              <Text style={[styles.tdR, pos ? styles.positive : styles.negative]}>
                {pos ? '+' : ''}{formatEgp(pp.gross_profit_egp)}
              </Text>
            </View>
          );
        })}
        {projectProfits.length === 0 && (
          <Text style={[styles.muted, { fontSize: 8, textAlign: 'center', marginTop: 6 }]}>
            No projects yet — لا توجد مشاريع بعد
          </Text>
        )}

        {/* Recent Transactions */}
        <Text style={styles.sectionTitle}>Recent Transactions / آخر المعاملات (Top {recentTx.length})</Text>
        <View style={styles.tableHeader}>
          <Text style={[styles.th, { flex: 1.1 }]}>Date</Text>
          <Text style={[styles.th, { flex: 0.7 }]}>Dir</Text>
          <Text style={[styles.th, { flex: 1.5 }]}>Category</Text>
          <Text style={[styles.th, { flex: 2 }]}>Project</Text>
          <Text style={[styles.th, { textAlign: 'right' }]}>EGP</Text>
        </View>
        {recentTx.map(tx => (
          <View key={tx.id} style={styles.tr}>
            <Text style={[styles.td, { flex: 1.1 }]}>{tx.transaction_date}</Text>
            <Text style={[styles.td, { flex: 0.7 }, tx.direction === 'income' ? styles.positive : styles.negative]}>
              {tx.direction === 'income' ? 'IN' : 'EX'}
            </Text>
            <Text style={[styles.td, { flex: 1.5 }]}>{tx.category}</Text>
            <Text style={[styles.td, { flex: 2 }]}>{tx.project_id?.slice(-8) ?? '—'}</Text>
            <Text style={[styles.tdR, tx.direction === 'income' ? styles.positive : styles.negative]}>
              {tx.direction === 'income' ? '+' : '−'}{formatEgp(tx.amount_egp)}
            </Text>
          </View>
        ))}

        {/* Open Obligations */}
        {openObls.length > 0 && (
          <>
            <Text style={styles.sectionTitle}>Open Obligations / الالتزامات المفتوحة ({openObls.length})</Text>
            <View style={styles.tableHeader}>
              <Text style={[styles.th, { flex: 1.5 }]}>Partner ID</Text>
              <Text style={styles.th}>Dir</Text>
              <Text style={styles.th}>Status</Text>
              <Text style={styles.th}>Due</Text>
              <Text style={[styles.th, { textAlign: 'right' }]}>Remaining EGP</Text>
            </View>
            {openObls.map(o => {
              const remaining = Math.max(0, o.amount_egp - o.amount_settled_egp);
              return (
                <View key={o.id} style={styles.tr}>
                  <Text style={[styles.td, { flex: 1.5 }]}>{o.partner_id.slice(-10)}</Text>
                  <Text style={[styles.td, o.direction === 'receivable' ? styles.positive : styles.negative]}>
                    {o.direction === 'receivable' ? 'REC' : 'PAY'}
                  </Text>
                  <Text style={styles.td}>{o.status}</Text>
                  <Text style={styles.td}>{o.due_date ?? '—'}</Text>
                  <Text style={styles.tdR}>{formatEgp(remaining)}</Text>
                </View>
              );
            })}
          </>
        )}

        {/* Footer */}
        <Text style={styles.footer} fixed>
          Terranex — Investment Operating System • Global P&L • All figures in EGP • Generated: {generatedAt}
          {'\n'}
          Profit = Σ Income − Σ Expense — كل رقم مالي مُتتبع لمصدره: معاملة + مستند + شريك
        </Text>
      </Page>
    </Document>
  );
}

export async function downloadGlobalPdf(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

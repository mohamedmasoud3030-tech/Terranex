import { useState } from 'react';
import { FileText } from 'lucide-react';
import { Button } from '../../components/ui/Button';
import { useProjects } from '../projects/hooks';
import { useTransactions } from '../transactions/hooks';
import { useObligations } from '../obligations/hooks';
import { computeGlobalSummary, computeProjectProfitability } from '../../core/lib/profitability';
import { useI18n } from '../../core/i18n/context';

export function ExportGlobalPdfButton() {
  const { locale } = useI18n();
  const { projects } = useProjects();
  const projectNames = new Map(projects.map(p => [p.id, p.name_ar]));
  const { transactions } = useTransactions();
  const { obligations } = useObligations();
  const [loading, setLoading] = useState(false);

  const hasData = projects.length > 0 || transactions.length > 0;

  async function handleExport() {
    setLoading(true);
    try {
      const global = computeGlobalSummary(projects, transactions, obligations);
      const projectProfits = projects
        .map(p => computeProjectProfitability(p, transactions, obligations, [], []))
        .sort((a, b) => b.gross_profit_egp - a.gross_profit_egp);

      const { pdf } = await import('@react-pdf/renderer');
      const { GlobalProfitabilityPdfDocument, downloadGlobalPdf } = await import('./GlobalProfitabilityPdf');

      const generatedAt = new Date().toISOString().replace('T', ' ').slice(0, 19);
      const blob = await pdf(
        <GlobalProfitabilityPdfDocument
          global={global}
          projectProfits={projectProfits}
          projectNames={projectNames}
          transactions={transactions}
          obligations={obligations}
          generatedAt={generatedAt}
          generatedBy={`Terranex v0.3.0 — ${locale.toUpperCase()}`}
        />
      ).toBlob();

      const filename = `Terranex-Global-PnL-${new Date().toISOString().slice(0, 10)}.pdf`;
      await downloadGlobalPdf(blob, filename);
    } catch (e) {
      console.error(e);
      alert(locale === 'ar' ? 'فشل تصدير PDF' : 'PDF export failed');
    } finally {
      setLoading(false);
    }
  }

  return (
    <Button
      variant="secondary"
      size="sm"
      onClick={handleExport}
      disabled={loading || !hasData}
      title={!hasData ? (locale === 'ar' ? 'لا توجد بيانات' : 'No data') : undefined}
    >
      <FileText className="h-4 w-4" />
      {loading
        ? (locale === 'ar' ? 'جار التوليد…' : 'Generating…')
        : (locale === 'ar' ? 'PDF شامل' : 'Export PDF')}
    </Button>
  );
}

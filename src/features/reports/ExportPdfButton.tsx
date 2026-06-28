import { useState } from 'react';
import { Download } from 'lucide-react';
import { Button } from '../../components/ui/Button';
import { useProject } from '../projects/hooks';
import { useTransactions } from '../transactions/hooks';
import { useObligations } from '../obligations/hooks';
import { usePartners } from '../partners/hooks';
import { computeProjectProfitability } from '../../core/lib/profitability';
import { projectPartnersStore } from '../partners/storage';
import { useI18n } from '../../core/i18n/context';

export function ExportProjectPdfButton({ projectId }: { projectId: string }) {
  const { locale } = useI18n();
  const project = useProject(projectId);
  const { transactions } = useTransactions(projectId);
  const { obligations } = useObligations(projectId);
  const { partners } = usePartners();
  const [loading, setLoading] = useState(false);

  if (!project) return null;

  async function handleExport() {
    if (!project) return;
    setLoading(true);
    try {
      const projectPartners = projectPartnersStore.getByProject(projectId);
      const profitability = computeProjectProfitability(
        project,
        transactions,
        obligations,
        projectPartners,
        partners
      );

      const { pdf } = await import('@react-pdf/renderer');
      const { ProjectProfitabilityPdfDocument, downloadProjectPdf } = await import('./ProjectProfitabilityPdf');

      const blob = await pdf(
        <ProjectProfitabilityPdfDocument
          project={project!}
          profitability={profitability}
          transactions={transactions}
          obligations={obligations}
          generatedAt={new Date().toISOString().replace('T', ' ').slice(0, 19)}
          generatedBy={`Terranex v0.4.0 — ${locale}`}
        />
      ).toBlob();

      const filename = `Terranex-PnL-${project.sector_id}-${project.id}-${new Date().toISOString().slice(0,10)}.pdf`;
      await downloadProjectPdf(blob, filename);
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
      disabled={loading}
    >
      <Download className="h-4 w-4" />
      {loading ? (locale==='ar' ? 'جار التوليد…' : 'Generating…') : (locale==='ar' ? 'تصدير PDF' : 'Export PDF')}
    </Button>
  );
}

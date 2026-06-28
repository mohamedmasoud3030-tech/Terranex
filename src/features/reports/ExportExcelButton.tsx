import { useState } from 'react';
import { FileSpreadsheet } from 'lucide-react';
import { Button } from '../../components/ui/Button';
import { useTransactions } from '../transactions/hooks';
import { useObligations } from '../obligations/hooks';
import { useProjects } from '../projects/hooks';
import { usePartners } from '../partners/hooks';
import { useDocuments } from '../documents/hooks';
import { useI18n } from '../../core/i18n/context';
import type { ExportLookups } from './financeExport';

interface ExportExcelButtonProps {
  /** Optional project scope. When omitted, exports the whole ledger. */
  projectId?: string;
  variant?: 'primary' | 'secondary';
  size?: 'sm' | 'md';
}

/**
 * Excel export button — transactions + obligations + summary.
 * The workbook builder is lazy-loaded (code-split) so it never weighs on the
 * initial bundle; it is fetched only when the user clicks "Export Excel".
 */
export function ExportExcelButton({
  projectId,
  variant = 'secondary',
  size = 'sm',
}: ExportExcelButtonProps) {
  const { locale } = useI18n();
  const { transactions } = useTransactions(projectId);
  const { obligations } = useObligations(projectId);
  const { projects } = useProjects();
  const { partners } = usePartners();
  const { documents } = useDocuments();
  const [loading, setLoading] = useState(false);

  async function handleExport() {
    setLoading(true);
    try {
      const projectNames = new Map(
        projects.map((p) => [p.id, locale === 'ar' ? p.name_ar : p.name_en || p.name_ar]),
      );
      const partnerNames = new Map(
        partners.map((p) => [p.id, locale === 'ar' ? p.name_ar : p.name_en || p.name_ar]),
      );
      const documentTitles = new Map(documents.map((d) => [d.id, d.title_ar]));

      const lookups: ExportLookups = {
        projectName: (id) => (id ? projectNames.get(id) ?? id : ''),
        partnerName: (id) => (id ? partnerNames.get(id) ?? id : ''),
        documentTitle: (id) => (id ? documentTitles.get(id) ?? id : ''),
      };

      const [{ buildFinanceWorkbookSheets }, { buildWorkbookBlob, downloadBlob }] =
        await Promise.all([import('./financeExport'), import('../../core/lib/xlsx')]);

      const sheets = buildFinanceWorkbookSheets(transactions, obligations, lookups, locale);
      const blob = buildWorkbookBlob(sheets);

      const scope = projectId ? `project-${projectId}` : 'all';
      const filename = `Terranex-Finance-${scope}-${new Date().toISOString().slice(0, 10)}.xls`;
      downloadBlob(blob, filename);
    } catch (e) {
      console.error(e);
      alert(locale === 'ar' ? 'فشل تصدير Excel' : 'Excel export failed');
    } finally {
      setLoading(false);
    }
  }

  const empty = transactions.length === 0 && obligations.length === 0;

  return (
    <Button
      variant={variant}
      size={size}
      onClick={handleExport}
      disabled={loading || empty}
      title={empty ? (locale === 'ar' ? 'لا توجد بيانات للتصدير' : 'No data to export') : undefined}
    >
      <FileSpreadsheet className="h-4 w-4" />
      {loading
        ? locale === 'ar'
          ? 'جارٍ التصدير…'
          : 'Exporting…'
        : locale === 'ar'
          ? 'تصدير Excel'
          : 'Export Excel'}
    </Button>
  );
}

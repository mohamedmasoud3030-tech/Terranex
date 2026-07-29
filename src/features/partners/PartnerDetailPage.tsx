import { useState } from 'react';
import { useRouter } from '@tanstack/react-router';
import { ArrowRight } from 'lucide-react';
import { AdaptiveFormSurface } from '../../components/ui/AdaptiveFormSurface';
import { Button } from '../../components/ui/Button';
import { ConfirmDialog } from '../../components/ui/ConfirmDialog';
import { FormErrorSummary } from '../../components/ui/FormContract';
import { ErrorState } from '../../components/ui/States';
import { WorkspaceLoadingState } from '../../components/workspace';
import { guardPartnerDeletion } from '../../core/lib/deletionGuards';
import { useI18n } from '../../core/i18n/context';
import type { PortfolioHandoff } from '../portfolio/contracts';
import { portfolioHandoffTarget } from '../integration';
import { PartnerWorkspaceView } from '../portfolio/PartnerWorkspaceView';
import { usePortfolioData } from '../portfolio/usePortfolioData';
import { PartnerForm } from './PartnerForm';
import {
  partnersHydration,
  partnersStore,
  type PartnerInput,
} from './storage';

export function PartnerDetailPage({ partnerId }: { partnerId: string }) {
  const router = useRouter();
  const { locale } = useI18n();
  const data = usePortfolioData();
  const partner = data.partners.find((item) => item.id === partnerId) ?? null;
  const [editing, setEditing] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [pending, setPending] = useState(false);
  const [serverError, setServerError] = useState<string | null>(null);
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;

  if (data.status === 'loading') {
    return <WorkspaceLoadingState label={label('جار تحميل مساحة الشريك', 'Loading partner workspace')} />;
  }
  if (data.status === 'error') {
    return <ErrorState title={label('تعذر تحميل الشريك', 'Could not load partner')} description={data.error?.message} onRetry={() => void data.retry()} />;
  }
  if (!partner) {
    return <ErrorState title={label('الشريك غير موجود', 'Partner not found')} description={label('قد يكون السجل حُذف أو أن الرابط غير صالح.', 'The record may have been deleted or the link is invalid.')} />;
  }
  const currentPartnerId = partner.id;

  function handoff(next: PortfolioHandoff) {
    void router.navigate(portfolioHandoffTarget(next) as never);
  }

  async function save(input: PartnerInput) {
    setPending(true);
    setServerError(null);
    try {
      partnersStore.update(currentPartnerId, input);
      await partnersHydration.flush();
      setEditing(false);
    } catch (error) {
      setServerError(error instanceof Error ? error.message : label('تعذر الحفظ.', 'Could not save.'));
    } finally {
      setPending(false);
    }
  }

  async function remove() {
    setPending(true);
    setServerError(null);
    try {
      const guard = await guardPartnerDeletion(currentPartnerId);
      if (!guard.canDelete) throw new Error(guard.message_ar);
      await partnersStore.remove(currentPartnerId);
      await partnersHydration.flush();
      setDeleteOpen(false);
      await router.navigate({ to: '/portfolio', search: { workspace: 'partners' } } as never);
    } catch (error) {
      setServerError(error instanceof Error ? error.message : label('تعذر الحذف.', 'Could not delete.'));
      setDeleteOpen(false);
    } finally {
      setPending(false);
    }
  }

  const formId = 'partner-workspace-form';
  return (
    <div className="space-y-4">
      <Button variant="ghost" onClick={() => void router.navigate({ to: '/portfolio', search: { workspace: 'partners' } } as never)}>
        <ArrowRight className="h-4 w-4" /> {label('العودة للشركاء', 'Back to partners')}
      </Button>
      {serverError && !editing && <ErrorState title={label('تعذر تنفيذ العملية', 'Action failed')} description={serverError} />}
      <PartnerWorkspaceView
        partner={partner}
        projects={data.projects}
        projectPartners={data.projectPartners}
        transactions={data.transactions}
        obligations={data.obligations}
        documents={data.documents}
        locale={locale}
        onEdit={() => {
          setServerError(null);
          setEditing(true);
        }}
        onDelete={() => setDeleteOpen(true)}
        onOpenProject={(project) => void router.navigate({ to: '/portfolio/projects/$id', params: { id: project.id } } as never)}
        onHandoff={handoff}
      />

      <AdaptiveFormSurface
        open={editing}
        onOpenChange={setEditing}
        title={label('تعديل الشريك أو الطرف', 'Edit partner or party')}
        description={label('يُغلق النموذج بعد تأكيد Supabase للحفظ.', 'The form closes after Supabase confirms the write.')}
        mode="edit"
        pending={pending}
        formId={formId}
        submitLabel={label('حفظ', 'Save')}
        cancelLabel={label('إلغاء', 'Cancel')}
        closeLabel={label('إغلاق', 'Close')}
        error={<FormErrorSummary title={label('تعذر الحفظ', 'Could not save')} serverError={serverError} />}
      >
        <PartnerForm
          formId={formId}
          hideActions
          initial={partner}
          onSubmit={save}
          onCancel={() => setEditing(false)}
        />
      </AdaptiveFormSurface>

      <ConfirmDialog
        open={deleteOpen}
        onOpenChange={setDeleteOpen}
        title={label('حذف الشريك؟', 'Delete partner?')}
        entityName={locale === 'ar' ? partner.name_ar : partner.name_en || partner.name_ar}
        impact={label('لن يُحذف السجل إذا كان مرتبطًا بمشروع أو معاملة أو ذمة أو مستند.', 'The record will not be deleted while linked to projects, transactions, obligations, or documents.')}
        confirmLabel={label('حذف', 'Delete')}
        cancelLabel={label('إلغاء', 'Cancel')}
        pending={pending}
        onConfirm={remove}
      />
    </div>
  );
}

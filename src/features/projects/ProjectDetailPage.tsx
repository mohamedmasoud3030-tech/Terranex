import { useState } from 'react';
import { useRouter } from '@tanstack/react-router';
import { ArrowRight } from 'lucide-react';
import { AdaptiveFormSurface } from '../../components/ui/AdaptiveFormSurface';
import { Button } from '../../components/ui/Button';
import { ConfirmDialog } from '../../components/ui/ConfirmDialog';
import { FormErrorSummary } from '../../components/ui/FormContract';
import { ErrorState } from '../../components/ui/States';
import { WorkspaceLoadingState } from '../../components/workspace';
import { guardProjectDeletion } from '../../core/lib/deletionGuards';
import { useI18n } from '../../core/i18n/context';
import { AssetForm } from '../assets/AssetForm';
import { assetsHydration, assetsStore, type AssetInput } from '../assets/storage';
import type { PortfolioHandoff } from '../portfolio/contracts';
import { portfolioHandoffTarget } from '../integration';
import { ProjectPartnerForm } from '../portfolio/ProjectPartnerForm';
import { ProjectWorkspaceView } from '../portfolio/ProjectWorkspaceView';
import { usePortfolioData } from '../portfolio/usePortfolioData';
import {
  projectPartnersHydration,
  projectPartnersStore,
  type ProjectPartnerInput,
} from '../partners/storage';
import { ProjectForm } from './ProjectForm';
import { projectsHydration, projectsStore, type ProjectInput } from './storage';

type Editor = 'project' | 'asset' | 'project-partner' | null;

export function ProjectDetailPage({ projectId }: { projectId: string }) {
  const router = useRouter();
  const { locale } = useI18n();
  const data = usePortfolioData();
  const [editor, setEditor] = useState<Editor>(null);
  const [pending, setPending] = useState(false);
  const [serverError, setServerError] = useState<string | null>(null);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);
  const project = data.projects.find((item) => item.id === projectId) ?? null;
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;

  if (data.status === 'loading') {
    return <WorkspaceLoadingState label={label('جار تحميل مساحة المشروع', 'Loading project workspace')} />;
  }
  if (data.status === 'error') {
    return (
      <ErrorState
        title={label('تعذر تحميل المشروع', 'Could not load project')}
        description={data.error?.message}
        onRetry={() => void data.retry()}
      />
    );
  }
  if (!project) {
    return (
      <ErrorState
        title={label('المشروع غير موجود', 'Project not found')}
        description={label('قد يكون المشروع حُذف أو أن الرابط غير صالح.', 'The project may have been deleted or the link is invalid.')}
        onRetry={() => void router.navigate({ to: '/portfolio', search: { workspace: 'projects' } } as never)}
      />
    );
  }
  const currentProjectId = project.id;

  async function write(operation: () => void, flush: () => Promise<void>) {
    setPending(true);
    setServerError(null);
    try {
      operation();
      await flush();
      setEditor(null);
    } catch (error) {
      setServerError(error instanceof Error ? error.message : label('تعذر الحفظ.', 'Could not save.'));
    } finally {
      setPending(false);
    }
  }

  function handoff(next: PortfolioHandoff) {
    void router.navigate(portfolioHandoffTarget(next) as never);
  }

  async function removeProject() {
    setPending(true);
    setDeleteError(null);
    try {
      const guard = await guardProjectDeletion(currentProjectId);
      if (!guard.canDelete) throw new Error(guard.message_ar);
      await projectsStore.remove(currentProjectId);
      await projectsHydration.flush();
      setDeleteOpen(false);
      await router.navigate({ to: '/portfolio', search: { workspace: 'projects' } } as never);
    } catch (error) {
      setDeleteError(error instanceof Error ? error.message : label('تعذر حذف المشروع.', 'Could not delete project.'));
      setDeleteOpen(false);
    } finally {
      setPending(false);
    }
  }

  const formId = 'project-workspace-context-form';
  return (
    <div className="space-y-4">
      <Button variant="ghost" onClick={() => void router.navigate({ to: '/portfolio', search: { workspace: 'projects' } } as never)}>
        <ArrowRight className="h-4 w-4" /> {label('العودة للمشاريع', 'Back to projects')}
      </Button>
      {deleteError && <ErrorState title={label('تعذر الحذف', 'Could not delete')} description={deleteError} />}
      <ProjectWorkspaceView
        project={project}
        assets={data.assets}
        partners={data.partners}
        projectPartners={data.projectPartners}
        transactions={data.transactions}
        obligations={data.obligations}
        documents={data.documents}
        events={data.events}
        locale={locale}
        onEditProject={() => {
          setServerError(null);
          setEditor('project');
        }}
        onDeleteProject={() => setDeleteOpen(true)}
        onAddAsset={() => {
          setServerError(null);
          setEditor('asset');
        }}
        onLinkPartner={() => {
          setServerError(null);
          setEditor('project-partner');
        }}
        onHandoff={handoff}
      />

      <AdaptiveFormSurface
        open={editor !== null}
        onOpenChange={(open) => { if (!open) setEditor(null); }}
        title={
          editor === 'project' ? label('تعديل المشروع', 'Edit project')
            : editor === 'asset' ? label('إضافة أصل للمشروع', 'Add project asset')
              : label('ربط شريك ملكية', 'Link equity partner')
        }
        description={label('لا يظهر النجاح قبل تأكيد Supabase.', 'Success is shown only after Supabase confirms the write.')}
        mode={editor === 'project' ? 'edit' : 'create'}
        pending={pending}
        formId={formId}
        submitLabel={label('حفظ', 'Save')}
        cancelLabel={label('إلغاء', 'Cancel')}
        closeLabel={label('إغلاق', 'Close')}
        error={<FormErrorSummary title={label('تعذر الحفظ', 'Could not save')} serverError={serverError} />}
      >
        {editor === 'project' && (
          <ProjectForm
            formId={formId}
            hideActions
            initial={project}
            loading={pending}
            onCancel={() => setEditor(null)}
            onSubmit={(input: ProjectInput) => write(
              () => projectsStore.update(project.id, input),
              projectsHydration.flush,
            )}
          />
        )}
        {editor === 'asset' && (
          <AssetForm
            formId={formId}
            hideActions
            pending={pending}
            projects={data.projects}
            projectLock={project.id}
            locale={locale}
            onCancel={() => setEditor(null)}
            onSubmit={(input: AssetInput) => write(
              () => assetsStore.create(input),
              assetsHydration.flush,
            )}
          />
        )}
        {editor === 'project-partner' && (
          <ProjectPartnerForm
            formId={formId}
            projectId={project.id}
            partners={data.partners}
            projectPartners={data.projectPartners}
            locale={locale}
            onSubmit={(input: ProjectPartnerInput) => write(
              () => projectPartnersStore.create(input),
              projectPartnersHydration.flush,
            )}
          />
        )}
      </AdaptiveFormSurface>

      <ConfirmDialog
        open={deleteOpen}
        onOpenChange={setDeleteOpen}
        title={label('حذف المشروع؟', 'Delete project?')}
        entityName={locale === 'ar' ? project.name_ar : project.name_en || project.name_ar}
        impact={label('سيُنفذ الحذف فقط إذا أكدت حواجز العلاقات أنه آمن، ولن تُحذف السجلات المرتبطة بصمت.', 'Deletion proceeds only if relationship guards confirm it is safe; linked records are never silently removed.')}
        confirmLabel={label('حذف المشروع', 'Delete project')}
        cancelLabel={label('إلغاء', 'Cancel')}
        pending={pending}
        onConfirm={removeProject}
      />
    </div>
  );
}

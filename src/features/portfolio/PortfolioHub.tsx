import { useEffect, useMemo, useRef, useState } from 'react';
import {
  ArrowRight,
  FolderKanban,
  LayoutDashboard,
  PackageOpen,
  Plus,
  Users,
} from 'lucide-react';
import { WorkspaceShell, useWorkspaceUrlState } from '../../components/workspace';
import { AdaptiveFormSurface } from '../../components/ui/AdaptiveFormSurface';
import { Button } from '../../components/ui/Button';
import { FormErrorSummary } from '../../components/ui/FormContract';
import { useI18n } from '../../core/i18n/context';
import { translateServerError } from '../../core/lib/serverErrorTranslator';
import type {
  Asset,
  AssetStatus,
  AssetType,
  Partner,
  PartnerCategory,
  Project,
  ProjectStatus,
  SectorId,
} from '../../core/types/domain';
import { AssetForm } from '../assets/AssetForm';
import { assetsHydration, assetsStore, type AssetInput } from '../assets/storage';
import { partnersHydration, partnersStore, projectPartnersHydration, projectPartnersStore, type PartnerInput, type ProjectPartnerInput } from '../partners/storage';
import { PartnerForm } from '../partners/PartnerForm';
import { ProjectForm } from '../projects/ProjectForm';
import { projectsHydration, projectsStore, type ProjectInput } from '../projects/storage';
import type { PortfolioActionHandlers, PortfolioHandoff } from './contracts';
import { PortfolioInspector, type InspectedEntity } from './PortfolioInspector';
import { PortfolioOverview } from './PortfolioOverview';
import { PartnerWorkspaceView } from './PartnerWorkspaceView';
import {
  AssetsWorkspace,
  PartnersWorkspace,
  ProjectsWorkspace,
} from './PortfolioWorkspaces';
import { ProjectPartnerForm } from './ProjectPartnerForm';
import { ProjectWorkspaceView } from './ProjectWorkspaceView';
import { usePortfolioData } from './usePortfolioData';

const WORKSPACE_IDS = ['overview', 'projects', 'assets', 'partners'] as const;
type PortfolioWorkspaceId = (typeof WORKSPACE_IDS)[number];
type EditorState =
  | { kind: 'project'; entity?: Project }
  | { kind: 'asset'; entity?: Asset; projectLock?: string }
  | { kind: 'partner'; entity?: Partner }
  | { kind: 'project-partner'; projectId: string }
  | null;

export function PortfolioHub({ onHandoff }: PortfolioActionHandlers) {
  const { locale } = useI18n();
  const data = usePortfolioData();
  const [workspace, setWorkspace] = useWorkspaceUrlState(
    WORKSPACE_IDS,
    'overview',
    { replace: false },
  );
  const activeWorkspace = workspace as PortfolioWorkspaceId;
  const [editor, setEditor] = useState<EditorState>(null);
  const [inspected, setInspected] = useState<InspectedEntity | null>(null);
  const [openProjectId, setOpenProjectId] = useState<string | null>(null);
  const [openPartnerId, setOpenPartnerId] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [serverError, setServerError] = useState<string | null>(null);
  const [projectQuery, setProjectQuery] = useState('');
  const [projectSector, setProjectSector] = useState<SectorId | 'all'>('all');
  const [projectStatus, setProjectStatus] = useState<ProjectStatus | 'all'>('all');
  const [assetQuery, setAssetQuery] = useState('');
  const [assetProject, setAssetProject] = useState<string | 'all'>('all');
  const [assetSector, setAssetSector] = useState<SectorId | 'all'>('all');
  const [assetType, setAssetType] = useState<AssetType | 'all'>('all');
  const [assetStatus, setAssetStatus] = useState<AssetStatus | 'all'>('all');
  const [partnerQuery, setPartnerQuery] = useState('');
  const [partnerCategory, setPartnerCategory] = useState<PartnerCategory | 'all'>('all');
  const initialIntentHandled = useRef(false);

  useEffect(() => {
    if (data.status !== 'ready' || initialIntentHandled.current) return;
    initialIntentHandled.current = true;
    const search = new URL(window.location.href).searchParams;
    const projectId = search.get('project');
    const partnerId = search.get('partner');
    const inspectId = search.get('inspect');
    const intent = search.get('intent');
    if (projectId && data.projects.some((item) => item.id === projectId)) {
      setWorkspace('projects');
      setOpenProjectId(projectId);
    } else if (partnerId && data.partners.some((item) => item.id === partnerId)) {
      setWorkspace('partners');
      setOpenPartnerId(partnerId);
    } else if (inspectId) {
      const project = data.projects.find((item) => item.id === inspectId);
      const asset = data.assets.find((item) => item.id === inspectId);
      const partner = data.partners.find((item) => item.id === inspectId);
      if (project) setInspected({ kind: 'project', value: project });
      else if (asset) setInspected({ kind: 'asset', value: asset });
      else if (partner) setInspected({ kind: 'partner', value: partner });
    }
    if (intent === 'create-project') startEditor({ kind: 'project' });
  }, [data, setWorkspace]);

  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;
  const workspaces = useMemo(() => [
    { id: 'overview', label: label('نظرة المحفظة', 'Portfolio overview'), description: label('مؤشرات ومتابعة العلاقات', 'KPIs and relationship attention'), icon: LayoutDashboard },
    { id: 'projects', label: label('المشاريع', 'Projects'), description: label('الكيان المحوري للمحفظة', 'The portfolio anchor'), icon: FolderKanban },
    { id: 'assets', label: label('الأصول', 'Assets'), description: label('الأصول داخل سياق المشروع', 'Assets in project context'), icon: PackageOpen },
    { id: 'partners', label: label('الشركاء والأطراف', 'Partners & parties'), description: label('ملكية وتعاملات', 'Equity and counterparties'), icon: Users },
    // locale is intentionally the only dependency; label is a local language selector.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  ], [locale]);
  const openProject = openProjectId
    ? data.projects.find((project) => project.id === openProjectId) ?? null
    : null;
  const openPartner = openPartnerId
    ? data.partners.find((partner) => partner.id === openPartnerId) ?? null
    : null;

  function openEntity(entity: 'project' | 'asset' | 'partner', id: string) {
    const value =
      entity === 'project' ? data.projects.find((item) => item.id === id)
        : entity === 'asset' ? data.assets.find((item) => item.id === id)
          : data.partners.find((item) => item.id === id);
    if (value) setInspected({ kind: entity, value } as InspectedEntity);
  }

  function openProjectWorkspace(project: Project) {
    setInspected(null);
    setOpenPartnerId(null);
    setWorkspace('projects');
    setOpenProjectId(project.id);
  }

  function openPartnerWorkspace(partner: Partner) {
    setInspected(null);
    setOpenProjectId(null);
    setWorkspace('partners');
    setOpenPartnerId(partner.id);
  }

  function startEditor(next: EditorState) {
    setServerError(null);
    setEditor(next);
  }

  async function runWrite(write: () => void, flush: () => Promise<void>) {
    setPending(true);
    setServerError(null);
    try {
      write();
      await flush();
      setEditor(null);
    } catch (error) {
      setServerError(translateServerError(error));
    } finally {
      setPending(false);
    }
  }

  const saveProject = (input: ProjectInput) =>
    runWrite(
      () => editor?.kind === 'project' && editor.entity
        ? projectsStore.update(editor.entity.id, input)
        : projectsStore.create(input),
      projectsHydration.flush,
    );
  const saveAsset = (input: AssetInput) =>
    runWrite(
      () => editor?.kind === 'asset' && editor.entity
        ? assetsStore.update(editor.entity.id, input)
        : assetsStore.create(input),
      assetsHydration.flush,
    );
  const savePartner = (input: PartnerInput) =>
    runWrite(
      () => editor?.kind === 'partner' && editor.entity
        ? partnersStore.update(editor.entity.id, input)
        : partnersStore.create(input),
      partnersHydration.flush,
    );
  const saveProjectPartner = (input: ProjectPartnerInput) =>
    runWrite(
      () => projectPartnersStore.create(input),
      projectPartnersHydration.flush,
    );

  function deliverHandoff(handoff: PortfolioHandoff) {
    onHandoff?.(handoff);
  }

  const action = openProject || openPartner ? (
    <Button variant="secondary" onClick={() => {
      setOpenProjectId(null);
      setOpenPartnerId(null);
    }}>
      <ArrowRight className="h-4 w-4" /> {openProject
        ? label('العودة لقائمة المشاريع', 'Back to projects')
        : label('العودة لقائمة الشركاء', 'Back to partners')}
    </Button>
  ) : activeWorkspace === 'assets' ? (
    <Button onClick={() => startEditor({ kind: 'asset' })} disabled={data.projects.length === 0}>
      <Plus className="h-4 w-4" /> {label('أصل جديد', 'New asset')}
    </Button>
  ) : activeWorkspace === 'partners' ? (
    <Button onClick={() => startEditor({ kind: 'partner' })}>
      <Plus className="h-4 w-4" /> {label('شريك أو طرف جديد', 'New partner or party')}
    </Button>
  ) : (
    <Button onClick={() => startEditor({ kind: 'project' })}>
      <Plus className="h-4 w-4" /> {label('مشروع جديد', 'New project')}
    </Button>
  );

  const state = data.status === 'loading' ? 'loading' : data.status === 'error' ? 'error' : 'ready';

  return (
    <>
      <WorkspaceShell
        title={label('المحفظة الاستثمارية', 'Investment portfolio')}
        description={label(
          'مساحة واحدة للمشاريع والأصول والشركاء، تحافظ على السياق من الفحص إلى التنفيذ.',
          'One connected space for projects, assets, and partners that preserves context from inspection to action.',
        )}
        actions={action}
        workspaces={workspaces}
        activeWorkspace={activeWorkspace}
        onWorkspaceChange={(next) => {
          setOpenProjectId(null);
          setOpenPartnerId(null);
          setWorkspace(next);
        }}
        switcherLabel={label('مساحات المحفظة', 'Portfolio workspaces')}
        loadingLabel={label('جار تحميل بيانات المحفظة', 'Loading portfolio data')}
        state={state}
        errorState={{
          title: label('تعذر تحميل المحفظة', 'Could not load portfolio'),
          description: data.error?.message ?? label('فشل تحميل بيانات Supabase.', 'Supabase data could not be loaded.'),
          onRetry: () => void data.retry(),
        }}
      >
        {openProject ? (
          <ProjectWorkspaceView
            project={openProject}
            assets={data.assets}
            partners={data.partners}
            projectPartners={data.projectPartners}
            transactions={data.transactions}
            obligations={data.obligations}
            documents={data.documents}
            events={data.events}
            locale={locale}
            embedded
            onEditProject={() => startEditor({ kind: 'project', entity: openProject })}
            onAddAsset={() => startEditor({ kind: 'asset', projectLock: openProject.id })}
            onLinkPartner={() => startEditor({ kind: 'project-partner', projectId: openProject.id })}
            onInspectAsset={(asset) => setInspected({ kind: 'asset', value: asset })}
            onInspectPartner={(partner) => setInspected({ kind: 'partner', value: partner })}
            onHandoff={deliverHandoff}
          />
        ) : openPartner ? (
          <PartnerWorkspaceView
            partner={openPartner}
            projects={data.projects}
            projectPartners={data.projectPartners}
            transactions={data.transactions}
            obligations={data.obligations}
            documents={data.documents}
            locale={locale}
            embedded
            onEdit={() => startEditor({ kind: 'partner', entity: openPartner })}
            onOpenProject={openProjectWorkspace}
            onHandoff={deliverHandoff}
          />
        ) : activeWorkspace === 'overview' ? (
          <PortfolioOverview
            projects={data.projects}
            assets={data.assets}
            partners={data.partners}
            projectPartners={data.projectPartners}
            locale={locale}
            onOpenEntity={openEntity}
          />
        ) : activeWorkspace === 'projects' ? (
          <ProjectsWorkspace
            projects={data.projects}
            transactions={data.transactions}
            obligations={data.obligations}
            projectPartners={data.projectPartners}
            partners={data.partners}
            locale={locale}
            query={projectQuery}
            sector={projectSector}
            status={projectStatus}
            onQuery={setProjectQuery}
            onSector={setProjectSector}
            onStatus={setProjectStatus}
            onInspect={(project) => setInspected({ kind: 'project', value: project })}
            onOpenWorkspace={openProjectWorkspace}
          />
        ) : activeWorkspace === 'assets' ? (
          <AssetsWorkspace
            assets={data.assets}
            projects={data.projects}
            locale={locale}
            query={assetQuery}
            projectId={assetProject}
            sector={assetSector}
            type={assetType}
            status={assetStatus}
            onQuery={setAssetQuery}
            onProject={setAssetProject}
            onSector={setAssetSector}
            onType={setAssetType}
            onStatus={setAssetStatus}
            onInspect={(asset) => setInspected({ kind: 'asset', value: asset })}
          />
        ) : (
          <PartnersWorkspace
            partners={data.partners}
            obligations={data.obligations}
            projectPartners={data.projectPartners}
            locale={locale}
            query={partnerQuery}
            category={partnerCategory}
            onQuery={setPartnerQuery}
            onCategory={setPartnerCategory}
            onInspect={(partner) => setInspected({ kind: 'partner', value: partner })}
            onOpenWorkspace={openPartnerWorkspace}
          />
        )}
      </WorkspaceShell>

      <PortfolioInspector
        entity={inspected}
        projects={data.projects}
        assets={data.assets}
        partners={data.partners}
        projectPartners={data.projectPartners}
        transactions={data.transactions}
        obligations={data.obligations}
        documents={data.documents}
        events={data.events}
        locale={locale}
        onClose={() => setInspected(null)}
        onEdit={(entity) => {
          setInspected(null);
          startEditor(entity.kind === 'project'
            ? { kind: 'project', entity: entity.value }
            : entity.kind === 'asset'
              ? { kind: 'asset', entity: entity.value }
              : { kind: 'partner', entity: entity.value });
        }}
        onOpenProject={openProjectWorkspace}
        onHandoff={deliverHandoff}
      />

      <PortfolioEditorSurface
        editor={editor}
        projects={data.projects}
        partners={data.partners}
        projectPartners={data.projectPartners}
        locale={locale}
        pending={pending}
        serverError={serverError}
        onClose={() => {
          setEditor(null);
          setServerError(null);
        }}
        onSaveProject={saveProject}
        onSaveAsset={saveAsset}
        onSavePartner={savePartner}
        onSaveProjectPartner={saveProjectPartner}
      />
    </>
  );
}

function PortfolioEditorSurface({
  editor,
  projects,
  partners,
  projectPartners,
  locale,
  pending,
  serverError,
  onClose,
  onSaveProject,
  onSaveAsset,
  onSavePartner,
  onSaveProjectPartner,
}: {
  editor: EditorState;
  projects: Project[];
  partners: Partner[];
  projectPartners: ReturnType<typeof projectPartnersStore.getAll>;
  locale: 'ar' | 'en';
  pending: boolean;
  serverError: string | null;
  onClose: () => void;
  onSaveProject: (input: ProjectInput) => Promise<void>;
  onSaveAsset: (input: AssetInput) => Promise<void>;
  onSavePartner: (input: PartnerInput) => Promise<void>;
  onSaveProjectPartner: (input: ProjectPartnerInput) => Promise<void>;
}) {
  if (!editor) return null;
  const label = (ar: string, en: string) => locale === 'ar' ? ar : en;
  const formId = 'portfolio-context-form';
  const editing = 'entity' in editor && Boolean(editor.entity);
  const title =
    editor.kind === 'project-partner' ? label('ربط شريك ملكية', 'Link equity partner')
      : editor.kind === 'project' ? (editing ? label('تعديل المشروع', 'Edit project') : label('مشروع جديد', 'New project'))
        : editor.kind === 'asset' ? (editing ? label('تعديل الأصل', 'Edit asset') : label('أصل جديد', 'New asset'))
          : (editing ? label('تعديل الشريك أو الطرف', 'Edit partner or party') : label('شريك أو طرف جديد', 'New partner or party'));
  const description =
    editor.kind === 'project-partner'
      ? label('يحافظ التحقق على ألا تتجاوز نسب الملكية الفعلية 100%.', 'Validation keeps active ownership at or below 100%.')
      : label('يُحفظ التغيير في Supabase قبل إعلان النجاح.', 'The change is confirmed by Supabase before success is shown.');

  return (
    <AdaptiveFormSurface
      open
      onOpenChange={(open) => { if (!open) onClose(); }}
      title={title}
      description={description}
      mode={editing ? 'edit' : 'create'}
      pending={pending}
      formId={formId}
      submitLabel={label('حفظ', 'Save')}
      cancelLabel={label('إلغاء', 'Cancel')}
      closeLabel={label('إغلاق النموذج', 'Close form')}
      error={<FormErrorSummary title={label('تعذر الحفظ', 'Could not save')} serverError={serverError} />}
    >
      {editor.kind === 'project' && (
        <ProjectForm
          formId={formId}
          hideActions
          initial={editor.entity}
          onSubmit={onSaveProject}
          onCancel={onClose}
          loading={pending}
        />
      )}
      {editor.kind === 'asset' && (
        <AssetForm
          formId={formId}
          hideActions
          pending={pending}
          projects={projects}
          projectLock={editor.projectLock}
          initial={editor.entity}
          locale={locale}
          onSubmit={onSaveAsset}
          onCancel={onClose}
        />
      )}
      {editor.kind === 'partner' && (
        <PartnerForm
          formId={formId}
          hideActions
          initial={editor.entity}
          onSubmit={onSavePartner}
          onCancel={onClose}
        />
      )}
      {editor.kind === 'project-partner' && (
        <ProjectPartnerForm
          formId={formId}
          projectId={editor.projectId}
          partners={partners}
          projectPartners={projectPartners}
          locale={locale}
          onSubmit={onSaveProjectPartner}
        />
      )}
    </AdaptiveFormSurface>
  );
}

import { useEffect, useMemo, useRef, useState } from 'react';
import { DatabaseZap, Download, FileArchive, Languages, LogOut, Palette, Plus, Settings2 } from 'lucide-react';
import { AdaptiveFormSurface } from '../../components/ui/AdaptiveFormSurface';
import { Badge } from '../../components/ui/Badge';
import { Button } from '../../components/ui/Button';
import { Card, CardContent, CardHeader } from '../../components/ui/Card';
import { ConfirmDialog } from '../../components/ui/ConfirmDialog';
import { EntityInspectorDrawer } from '../../components/ui/EntityInspectorDrawer';
import { WorkspaceShell, useWorkspaceUrlState } from '../../components/workspace';
import { useAuth } from '../../core/auth/AuthProvider';
import { useI18n } from '../../core/i18n/context';
import { downloadBlob } from '../../core/lib/download';
import { translateServerError } from '../../core/lib/serverErrorTranslator';
import {
  deleteDocumentFile,
  getDocumentFile,
  makeLocalDocumentFileUrl,
  saveDocumentFile,
} from '../../core/storage/indexedDbFileStore';
import { useTheme, type ThemeMode } from '../../core/theme';
import type { Document } from '../../core/types/domain';
import { documentsHydration, documentsStore } from '../documents/storage';
import { BackupRestoreSection } from '../settings/BackupRestoreSection';
import { ExchangeRateSection } from '../settings/ExchangeRateSection';
import { classifyDocumentExpiry, inspectOrphanReferences } from './dataHealth';
import type { GovernanceHandoff } from './contracts';
import { DocumentForm, type DocumentDraft } from './DocumentForm';
import { useGovernanceData } from './useGovernanceData';

const workspaceIds = ['documents', 'settings', 'exchange-rates', 'data-health'] as const;
type WorkspaceId = typeof workspaceIds[number];

export function GovernanceHub({ onHandoff }: { onHandoff?: (handoff: GovernanceHandoff) => void }) {
  const { locale } = useI18n();
  const { records, diagnostics, loading } = useGovernanceData();
  const [workspace, setWorkspace] = useWorkspaceUrlState(workspaceIds, 'documents', { parameter: 'workspace' });
  const [selectedDocument, setSelectedDocument] = useState<Document>();
  const [formOpen, setFormOpen] = useState(false);
  const [documentPending, setDocumentPending] = useState(false);
  const [documentError, setDocumentError] = useState('');
  const [filters, setFilters] = useState(() => {
    const search = new URL(window.location.href).searchParams;
    return {
      type: search.get('type') ?? 'all',
      projectId: search.get('project') ?? '',
      assetId: search.get('asset') ?? '',
      partnerId: search.get('partner') ?? '',
      expiry: search.get('expiry') ?? 'all',
    };
  });
  const initialIntentHandled = useRef(false);
  const asOf = new Date().toISOString().slice(0, 10);
  const findings = useMemo(() => inspectOrphanReferences(records), [records]);
  const filteredDocuments = useMemo(() => records.documents.filter((item) => {
    const expiry = classifyDocumentExpiry(item.expiry_date, asOf);
    return (filters.type === 'all' || item.type === filters.type)
      && (!filters.projectId || item.project_id === filters.projectId)
      && (!filters.assetId || item.asset_id === filters.assetId)
      && (!filters.partnerId || item.partner_id === filters.partnerId)
      && (filters.expiry === 'all' || expiry === filters.expiry);
  }), [asOf, filters, records.documents]);
  const projectNames = new Map(records.projects.map((item) => [item.id, locale === 'ar' ? item.name_ar : item.name_en]));
  const partnerNames = new Map(records.partners.map((item) => [item.id, locale === 'ar' ? item.name_ar : item.name_en ?? item.name_ar]));

  function commitFilters(next: typeof filters) {
    const url = new URL(window.location.href);
    for (const key of ['project', 'asset', 'partner', 'type', 'expiry']) url.searchParams.delete(key);
    const values = {
      project: next.projectId,
      asset: next.assetId,
      partner: next.partnerId,
      type: next.type === 'all' ? undefined : next.type,
      expiry: next.expiry === 'all' ? undefined : next.expiry,
    };
    for (const [key, value] of Object.entries(values)) if (value) url.searchParams.set(key, value);
    window.history.replaceState(window.history.state, '', url);
    setFilters(next);
  }

  useEffect(() => {
    if (loading || initialIntentHandled.current) return;
    initialIntentHandled.current = true;
    const search = new URL(window.location.href).searchParams;
    const inspectId = search.get('inspect');
    const item = records.documents.find((documentItem) => documentItem.id === inspectId);
    if (item) setSelectedDocument(item);
    if (search.get('intent') === 'attach-document') setFormOpen(true);
  }, [loading, records.documents]);

  const workspaces = [
    { id: 'documents', label: locale === 'ar' ? 'خزنة المستندات' : 'Document vault', icon: FileArchive },
    { id: 'settings', label: locale === 'ar' ? 'الإعدادات' : 'Settings', icon: Settings2 },
    { id: 'exchange-rates', label: locale === 'ar' ? 'أسعار الصرف' : 'Exchange rates', icon: DatabaseZap },
    { id: 'data-health', label: locale === 'ar' ? 'صحة البيانات' : 'Data health', icon: DatabaseZap },
  ];

  async function createDocument(draft: DocumentDraft) {
    setDocumentPending(true);
    setDocumentError('');
    let created: Document | undefined;
    let localFileUrl: string | undefined;
    try {
      created = documentsStore.create(draft.input);
      await documentsHydration.flush();
      const storedFile = await saveDocumentFile(created.id, draft.file);
      localFileUrl = makeLocalDocumentFileUrl(created.id);
      documentsStore.update(created.id, {
        file_url: localFileUrl,
        file_name: storedFile.original_file_name,
        file_mime_type: storedFile.mime_type,
        file_size_bytes: storedFile.size_bytes,
        file_sha256: storedFile.sha256,
      });
      await documentsHydration.flush();
      setFormOpen(false);
    } catch (cause) {
      if (localFileUrl) await deleteDocumentFile(localFileUrl).catch(() => undefined);
      if (created && documentsStore.getAll().some((item) => item.id === created?.id)) {
        await documentsStore.remove(created.id).then(() => documentsHydration.flush()).catch(() => documentsHydration.rehydrate());
      }
      setDocumentError(translateServerError(cause));
      throw cause;
    } finally {
      setDocumentPending(false);
    }
  }

  async function downloadDocument(item: Document) {
    if (!item.file_url) return;
    const stored = await getDocumentFile(item.file_url);
    if (!stored) {
      setDocumentError(locale === 'ar' ? 'الملف المحلي غير موجود على هذا الجهاز.' : 'The local file is not available on this device.');
      return;
    }
    downloadBlob(stored.blob, item.file_name ?? stored.original_file_name);
  }

  return (
    <>
      <WorkspaceShell
        title={locale === 'ar' ? 'مركز الحوكمة' : 'Governance Hub'}
        description={locale === 'ar' ? 'المستندات والسياسات والإعدادات وصحة البيانات في سطح تشغيلي واحد.' : 'Documents, policy, settings, and data health in one operating surface.'}
        workspaces={workspaces}
        activeWorkspace={workspace}
        onWorkspaceChange={(value) => setWorkspace(value as WorkspaceId)}
        switcherLabel={locale === 'ar' ? 'مساحات الحوكمة' : 'Governance workspaces'}
        loadingLabel={locale === 'ar' ? 'جار تحميل الحوكمة' : 'Loading governance'}
        state={loading ? 'loading' : 'ready'}
        actions={workspace === 'documents' ? <Button onClick={() => setFormOpen(true)}><Plus className="h-4 w-4" />{locale === 'ar' ? 'مستند جديد' : 'New document'}</Button> : undefined}
        summaries={workspace === 'documents' ? <DocumentFilters filters={filters} locale={locale} records={records} onChange={commitFilters} /> : undefined}
      >
        {workspace === 'documents' && (
          <DocumentVault
            documents={filteredDocuments}
            locale={locale}
            projectNames={projectNames}
            partnerNames={partnerNames}
            asOf={asOf}
            onSelect={setSelectedDocument}
          />
        )}
        {workspace === 'settings' && <SettingsWorkspace locale={locale} />}
        {workspace === 'exchange-rates' && <ExchangeRateSection locale={locale} />}
        {workspace === 'data-health' && <DataHealthWorkspace diagnostics={diagnostics} findings={findings} locale={locale} onHandoff={onHandoff} />}
      </WorkspaceShell>

      <AdaptiveFormSurface
        open={formOpen}
        onOpenChange={setFormOpen}
        title={locale === 'ar' ? 'إضافة مستند' : 'Add document'}
        description={locale === 'ar' ? 'نفس النموذج يدعم الخزنة العامة وسياق المشروع أو الطرف.' : 'The same form contract supports the global vault and project or partner context.'}
        closeLabel={locale === 'ar' ? 'إغلاق' : 'Close'}
        cancelLabel={locale === 'ar' ? 'إلغاء' : 'Cancel'}
        submitLabel={locale === 'ar' ? 'حفظ المستند' : 'Save document'}
        formId="governance-document-form"
        pending={documentPending}
        error={documentError ? <p role="alert" className="mb-3 rounded-xl border border-danger/30 bg-danger/5 p-3 text-sm text-danger">{documentError}</p> : undefined}
      >
        <DocumentForm
          key={`${filters.projectId}:${filters.assetId}:${filters.partnerId}:${formOpen}`}
          formId="governance-document-form"
          projects={records.projects}
          partners={records.partners}
          initialProjectId={filters.projectId || undefined}
          assets={records.assets}
          initialAssetId={filters.assetId || undefined}
          initialPartnerId={filters.partnerId || undefined}
          onSubmit={createDocument}
        />
      </AdaptiveFormSurface>

      <DocumentInspector
        item={selectedDocument}
        locale={locale}
        projectName={selectedDocument?.project_id ? projectNames.get(selectedDocument.project_id) : undefined}
        partnerName={selectedDocument?.partner_id ? partnerNames.get(selectedDocument.partner_id) : undefined}
        onClose={() => setSelectedDocument(undefined)}
        onDownload={downloadDocument}
      />
    </>
  );
}

function DocumentFilters({ filters, locale, records, onChange }: { filters: { type: string; projectId: string; assetId: string; partnerId: string; expiry: string }; locale: 'ar' | 'en'; records: ReturnType<typeof useGovernanceData>['records']; onChange: (value: typeof filters) => void }) {
  const inputClass = 'min-h-11 rounded-xl border bg-card px-3 text-sm';
  return <div className="grid gap-3 rounded-2xl border bg-muted/20 p-3 sm:grid-cols-2 xl:grid-cols-5"><select aria-label="Document type" className={inputClass} value={filters.type} onChange={(event) => onChange({ ...filters, type: event.target.value })}><option value="all">All types</option><option value="contract">Contract</option><option value="invoice">Invoice</option><option value="receipt">Receipt</option><option value="permit">Permit</option><option value="other">Other</option></select><select aria-label="Project" className={inputClass} value={filters.projectId} onChange={(event) => onChange({ ...filters, projectId: event.target.value, assetId: '' })}><option value="">All projects</option>{records.projects.map((item) => <option key={item.id} value={item.id}>{locale === 'ar' ? item.name_ar : item.name_en}</option>)}</select><select aria-label="Asset" className={inputClass} value={filters.assetId} onChange={(event) => onChange({ ...filters, assetId: event.target.value })}><option value="">All assets</option>{records.assets.filter((item) => !filters.projectId || item.project_id === filters.projectId).map((item) => <option key={item.id} value={item.id}>{locale === 'ar' ? item.name_ar : item.name_en}</option>)}</select><select aria-label="Partner" className={inputClass} value={filters.partnerId} onChange={(event) => onChange({ ...filters, partnerId: event.target.value })}><option value="">All partners</option>{records.partners.map((item) => <option key={item.id} value={item.id}>{locale === 'ar' ? item.name_ar : item.name_en ?? item.name_ar}</option>)}</select><select aria-label="Expiry state" className={inputClass} value={filters.expiry} onChange={(event) => onChange({ ...filters, expiry: event.target.value })}><option value="all">All expiry states</option><option value="current">Current</option><option value="expiring">Expiring in 30 days</option><option value="expired">Expired</option><option value="undated">No expiry date</option></select></div>;
}

function DocumentVault({ documents, locale, projectNames, partnerNames, asOf, onSelect }: { documents: Document[]; locale: 'ar' | 'en'; projectNames: Map<string, string>; partnerNames: Map<string, string>; asOf: string; onSelect: (item: Document) => void }) {
  return <Card><CardHeader><h2 className="font-bold">{locale === 'ar' ? 'الخزنة العامة' : 'Global vault'} · {documents.length}</h2></CardHeader><CardContent><div className="divide-y rounded-xl border">{documents.map((item) => { const expiry = classifyDocumentExpiry(item.expiry_date, asOf); return <button key={item.id} onClick={() => onSelect(item)} className="grid min-h-16 w-full gap-2 p-3 text-start sm:grid-cols-[1fr_auto]"><span><strong className="block">{item.title_ar}</strong><span className="text-xs text-muted-foreground">{item.type} · {item.project_id ? projectNames.get(item.project_id) ?? item.project_id : '—'}{item.partner_id ? ` · ${partnerNames.get(item.partner_id) ?? item.partner_id}` : ''}</span></span><Badge tone={expiry === 'expired' ? 'negative' : expiry === 'expiring' ? 'warning' : 'neutral'}>{expiry}</Badge></button>; })}</div>{documents.length === 0 && <p className="py-8 text-center text-sm text-muted-foreground">{locale === 'ar' ? 'لا توجد مستندات تطابق الفلاتر.' : 'No documents match the filters.'}</p>}</CardContent></Card>;
}

function DocumentInspector({ item, locale, projectName, partnerName, onClose, onDownload }: { item?: Document; locale: 'ar' | 'en'; projectName?: string; partnerName?: string; onClose: () => void; onDownload: (item: Document) => void | Promise<void> }) {
  return <EntityInspectorDrawer open={Boolean(item)} onOpenChange={(open) => { if (!open) onClose(); }} title={item?.title_ar ?? ''} description={item?.type} closeLabel={locale === 'ar' ? 'إغلاق' : 'Close'} relationshipsLabel={locale === 'ar' ? 'الروابط' : 'Relationships'} activityLabel={locale === 'ar' ? 'تفاصيل الملف' : 'File details'} summary={<div className="space-y-2 text-sm"><p>{locale === 'ar' ? 'الإصدار' : 'Issued'}: {item?.issue_date ?? '—'}</p><p>{locale === 'ar' ? 'الانتهاء' : 'Expiry'}: {item?.expiry_date ?? '—'}</p></div>} relationships={<div className="space-y-2 text-sm"><p>{locale === 'ar' ? 'المشروع' : 'Project'}: {projectName ?? '—'}</p><p>{locale === 'ar' ? 'الطرف' : 'Partner'}: {partnerName ?? '—'}</p><p>Transaction: {item?.transaction_id ?? '—'}</p></div>} activity={<div className="space-y-2 text-sm"><p>{item?.file_name ?? (locale === 'ar' ? 'لا يوجد ملف محلي' : 'No local file')}</p><p>{item?.file_mime_type ?? '—'}</p></div>} actions={item?.file_url ? <Button variant="secondary" onClick={() => void onDownload(item)}><Download className="h-4 w-4" />{locale === 'ar' ? 'تنزيل' : 'Download'}</Button> : undefined} />;
}

function SettingsWorkspace({ locale }: { locale: 'ar' | 'en' }) {
  const { setLocale } = useI18n();
  const { mode, setMode } = useTheme();
  const { user, signOut } = useAuth();
  const [confirmSignOut, setConfirmSignOut] = useState(false);
  const themes: ThemeMode[] = ['light', 'dark', 'system'];
  return <div className="grid gap-4 xl:grid-cols-3"><Card><CardContent><Languages className="h-5 w-5 text-primary" /><h2 className="mt-3 font-bold">{locale === 'ar' ? 'اللغة والاتجاه' : 'Language & direction'}</h2><div className="mt-3 flex gap-2"><Button variant={locale === 'ar' ? 'primary' : 'secondary'} onClick={() => setLocale('ar')}>العربية</Button><Button variant={locale === 'en' ? 'primary' : 'secondary'} onClick={() => setLocale('en')}>English</Button></div></CardContent></Card><Card><CardContent><Palette className="h-5 w-5 text-primary" /><h2 className="mt-3 font-bold">{locale === 'ar' ? 'المظهر' : 'Appearance'}</h2><div className="mt-3 flex flex-wrap gap-2">{themes.map((item) => <Button key={item} variant={mode === item ? 'primary' : 'secondary'} onClick={() => setMode(item)}>{item}</Button>)}</div></CardContent></Card><Card><CardContent><h2 className="font-bold">{locale === 'ar' ? 'الحساب والجلسة' : 'Account & session'}</h2><p className="mt-2 break-all text-sm text-muted-foreground">{user?.email ?? '—'}</p><p className="mt-1 text-xs text-muted-foreground">{locale === 'ar' ? 'لا توجد أدوار وهمية في الواجهة؛ الصلاحيات يحددها Supabase.' : 'No invented UI roles; Supabase owns authorization.'}</p><Button variant="danger" className="mt-4" onClick={() => setConfirmSignOut(true)}><LogOut className="h-4 w-4" />{locale === 'ar' ? 'تسجيل الخروج' : 'Sign out'}</Button></CardContent></Card><BackupRestoreSection locale={locale} /><ConfirmDialog open={confirmSignOut} onOpenChange={setConfirmSignOut} title={locale === 'ar' ? 'تأكيد تسجيل الخروج' : 'Confirm sign out'} entityName={user?.email ?? 'Current session'} impact={locale === 'ar' ? 'ستنتهي الجلسة الحالية وتُمسح ذاكرة البيانات عند انتقال الهوية.' : 'The current session ends and identity-scoped caches will be cleared by the auth flow.'} confirmLabel={locale === 'ar' ? 'تسجيل الخروج' : 'Sign out'} cancelLabel={locale === 'ar' ? 'إلغاء' : 'Cancel'} onConfirm={signOut} /></div>;
}

function DataHealthWorkspace({ diagnostics, findings, locale, onHandoff }: { diagnostics: ReturnType<typeof useGovernanceData>['diagnostics']; findings: ReturnType<typeof inspectOrphanReferences>; locale: 'ar' | 'en'; onHandoff?: (handoff: GovernanceHandoff) => void }) {
  const unhealthyStores = diagnostics.filter((item) => item.loadError || item.writeError || !item.loaded || item.readsBeforeHydration > 0);
  return <div className="space-y-4"><Card><CardHeader><h2 className="font-bold">{locale === 'ar' ? 'حالة القراءة والكتابة' : 'Hydration & write status'}</h2></CardHeader><CardContent><div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-3">{diagnostics.map((item) => <div key={item.name} className="rounded-xl border p-3 text-sm"><div className="flex justify-between gap-2"><strong>{item.name}</strong><Badge tone={item.loadError || item.writeError ? 'negative' : item.loaded ? 'positive' : 'warning'}>{item.loaded ? 'loaded' : 'loading'}</Badge></div>{item.loadError && <p className="mt-2 text-danger">{item.loadError}</p>}{item.writeError && <p className="mt-2 text-danger">{item.writeError}</p>}{item.readsBeforeHydration > 0 && <p className="mt-2 text-warning">{item.readsBeforeHydration} early reads</p>}</div>)}</div><p className="mt-3 text-xs text-muted-foreground">{unhealthyStores.length === 0 ? (locale === 'ar' ? 'لا توجد أخطاء تخزين مرصودة.' : 'No observed storage errors.') : `${unhealthyStores.length} stores need attention.`}</p></CardContent></Card><Card><CardHeader><h2 className="font-bold">{locale === 'ar' ? 'المراجع اليتيمة' : 'Orphan references'} · {findings.length}</h2></CardHeader><CardContent><p className="mb-3 text-sm text-muted-foreground">{locale === 'ar' ? 'الفحص تشخيصي فقط ولا يغيّر أي سجل أو ينفذ إصلاحًا تلقائيًا.' : 'This scanner is diagnostic-only. It never changes records or runs automatic repair.'}</p><div className="divide-y rounded-xl border">{findings.map((item) => <div key={`${item.code}:${item.entityId}`} className="flex flex-col justify-between gap-2 p-3 text-sm sm:flex-row sm:items-center"><span><strong>{item.entity}:{item.entityId}</strong><span className="block text-xs text-muted-foreground">{item.relationship} → {item.missingId}</span></span>{onHandoff && <Button variant="secondary" size="sm" onClick={() => onHandoff({ destination: item.entity === 'transaction' || item.entity === 'obligation' ? 'finance' : item.entity === 'event' || item.entity === 'adjustment' ? 'operations' : 'portfolio', entityId: item.entityId, relationship: item.relationship })}>{locale === 'ar' ? 'فتح السياق' : 'Open context'}</Button>}</div>)}</div>{findings.length === 0 && <p className="py-6 text-center text-sm text-muted-foreground">{locale === 'ar' ? 'لا توجد مراجع يتيمة في اللقطة الحالية.' : 'No orphan references in the current snapshot.'}</p>}</CardContent></Card></div>;
}

import { useRef, useState } from 'react';
import { Download, Upload, Trash2 } from 'lucide-react';
import { Button } from '../../components/ui/Button';
import { Card, CardContent } from '../../components/ui/Card';
import {
  clearTerranexArchiveData,
  createTerranexArchive,
  parseTerranexArchive,
  restoreTerranexArchive,
  type ParsedTerranexArchive,
} from '../../core/storage/archiveBackup';
import type { Locale } from '../../core/types';

function downloadArchive(bytes: Uint8Array, exportedAt: string, prefix = 'terranex-backup') {
  const blob = new Blob([bytes], { type: 'application/zip' });
  const href = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = href;
  link.download = `${prefix}-${exportedAt.slice(0, 19).replace(/[:T]/g, '-')}.zip`;
  link.click();
  URL.revokeObjectURL(href);
}

function formatBytes(bytes: number) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export function BackupRestoreSection({ locale }: { locale: Locale }) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [pending, setPending] = useState<ParsedTerranexArchive | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const summary = pending?.summary ?? null;
  const ar = locale === 'ar';

  function resetMessage() {
    setMessage('');
    setError('');
  }

  async function exportBackup(prefix = 'terranex-backup') {
    resetMessage();
    setBusy(true);
    try {
      const archive = await createTerranexArchive();
      downloadArchive(archive.bytes, archive.manifest.exported_at, prefix);
      setMessage(ar ? 'تم إنشاء ملف ZIP يشمل السجلات والملفات المحلية.' : 'ZIP backup created with records and local files.');
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'تعذر إنشاء ملف النسخة الاحتياطية.');
      throw cause;
    } finally {
      setBusy(false);
    }
  }

  async function selectBackup(file?: File) {
    resetMessage();
    setPending(null);
    if (!file) return;
    setBusy(true);
    try {
      setPending(parseTerranexArchive(new Uint8Array(await file.arrayBuffer())));
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'تعذر قراءة ملف النسخة الاحتياطية.');
    } finally {
      setBusy(false);
      if (inputRef.current) inputRef.current.value = '';
    }
  }

  async function applyRestore() {
    if (!pending) return;
    const confirmed = window.confirm(ar
      ? 'سيتم استبدال سجلات Terranex وملفاته المحلية بالنسخة المختارة. هل تريد المتابعة؟'
      : 'Current Terranex records and local files will be replaced. Continue?');
    if (!confirmed) return;

    resetMessage();
    setBusy(true);
    try {
      const safetyCopy = await createTerranexArchive();
      downloadArchive(safetyCopy.bytes, safetyCopy.manifest.exported_at, 'terranex-pre-restore');
      await restoreTerranexArchive(pending);
      window.location.reload();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'تعذر استعادة النسخة الاحتياطية.');
      setBusy(false);
    }
  }

  async function clearData() {
    resetMessage();
    const first = window.confirm(ar
      ? 'سيتم حذف جميع سجلات Terranex وملفاته المحلية من هذا المتصفح. هل تريد المتابعة؟'
      : 'All local Terranex records and files will be deleted from this browser. Continue?');
    if (!first) return;
    const second = window.confirm(ar
      ? 'تأكيد أخير: لا يمكن التراجع عن المسح إلا باستخدام نسخة احتياطية ZIP. هل تريد الحذف؟'
      : 'Final confirmation: deletion can only be reversed with a ZIP backup. Delete now?');
    if (!second) return;

    setBusy(true);
    try {
      const safetyCopy = await createTerranexArchive();
      downloadArchive(safetyCopy.bytes, safetyCopy.manifest.exported_at, 'terranex-pre-clear');
      await clearTerranexArchiveData();
      window.location.reload();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'تعذر مسح البيانات المحلية.');
      setBusy(false);
    }
  }

  return (
    <Card className="xl:col-span-3">
      <CardContent>
        <h3 className="mb-2 text-lg font-bold">{ar ? 'النسخ الاحتياطي والاستعادة' : 'Backup & Restore'}</h3>
        <p className="mb-4 text-sm leading-7 text-muted-foreground">
          {ar
            ? 'احفظ حزمة ZIP تشمل سجلات Terranex والملفات المحلية المرفوعة، أو استعد نسخة سابقة بعد التحقق من سلامتها. يتم تنزيل نسخة أمان تلقائيًا قبل الاستعادة أو المسح.'
            : 'Export a ZIP package with Terranex records and uploaded local files, or restore a validated archive. A safety copy is downloaded automatically before restore or clear actions.'}
        </p>

        <div className="flex flex-wrap gap-2">
          <Button type="button" variant="secondary" disabled={busy} onClick={() => void exportBackup()}>
            <Download className="h-4 w-4" />
            {ar ? 'تصدير نسخة ZIP احتياطية' : 'Export ZIP backup'}
          </Button>
          <Button type="button" variant="secondary" disabled={busy} onClick={() => inputRef.current?.click()}>
            <Upload className="h-4 w-4" />
            {ar ? 'اختيار ملف ZIP للاستعادة' : 'Choose ZIP restore file'}
          </Button>
          <input
            ref={inputRef}
            type="file"
            accept="application/zip,.zip"
            className="hidden"
            onChange={(event) => void selectBackup(event.target.files?.[0])}
          />
        </div>

        {summary && (
          <div className="mt-4 rounded-xl border border-border bg-muted p-4 text-sm">
            <p className="font-bold">{ar ? 'ملخص النسخة المختارة' : 'Selected backup summary'}</p>
            <p className="mt-1 text-muted-foreground">
              {ar
                ? `${summary.keys} مفاتيح تخزين و${summary.records} سجلات و${summary.files} ملفات محلية بحجم ${formatBytes(summary.total_file_bytes)}.`
                : `${summary.keys} storage keys, ${summary.records} collection records, and ${summary.files} local files totaling ${formatBytes(summary.total_file_bytes)}.`}
            </p>
            <Button type="button" className="mt-3" disabled={busy} onClick={() => void applyRestore()}>
              {ar ? 'استعادة النسخة المختارة' : 'Restore selected backup'}
            </Button>
          </div>
        )}

        {message && <p className="mt-3 text-sm text-success">{message}</p>}
        {error && <p className="mt-3 text-sm text-danger">{error}</p>}

        <div className="mt-6 rounded-xl border border-danger/30 bg-danger/5 p-4">
          <h4 className="font-bold text-danger">{ar ? 'منطقة خطرة' : 'Danger zone'}</h4>
          <p className="mt-1 text-sm leading-6 text-muted-foreground">
            {ar ? 'استخدم المسح فقط عند الحاجة إلى بدء نسخة محلية فارغة. سيشمل المسح السجلات والملفات المرفوعة.' : 'Clear data only when you need to start with an empty local workspace. Records and uploaded files will be removed together.'}
          </p>
          <Button type="button" variant="danger" className="mt-3" disabled={busy} onClick={() => void clearData()}>
            <Trash2 className="h-4 w-4" />
            {ar ? 'مسح بيانات Terranex المحلية' : 'Clear local Terranex data'}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}

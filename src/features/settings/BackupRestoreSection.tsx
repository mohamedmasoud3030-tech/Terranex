import { useRef, useState } from 'react';
import { Download, Upload, Trash2 } from 'lucide-react';
import { Button } from '../../components/ui/Button';
import { Card, CardContent } from '../../components/ui/Card';
import {
  clearTerranexData,
  createTerranexBackup,
  parseTerranexBackup,
  restoreTerranexBackup,
  summarizeTerranexRecords,
  type TerranexBackup,
} from '../../core/storage/backup';
import type { Locale } from '../../core/types';

function downloadBackup(backup: TerranexBackup, prefix = 'terranex-backup') {
  const blob = new Blob([JSON.stringify(backup, null, 2)], { type: 'application/json;charset=utf-8' });
  const href = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = href;
  link.download = `${prefix}-${backup.exported_at.slice(0, 19).replace(/[:T]/g, '-')}.json`;
  link.click();
  URL.revokeObjectURL(href);
}

export function BackupRestoreSection({ locale }: { locale: Locale }) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [pending, setPending] = useState<TerranexBackup | null>(null);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const summary = pending ? summarizeTerranexRecords(pending.records) : null;
  const ar = locale === 'ar';

  function resetMessage() {
    setMessage('');
    setError('');
  }

  function exportBackup() {
    resetMessage();
    downloadBackup(createTerranexBackup());
    setMessage(ar ? 'تم إنشاء ملف النسخة الاحتياطية.' : 'Backup file created.');
  }

  async function selectBackup(file?: File) {
    resetMessage();
    setPending(null);
    if (!file) return;
    try {
      setPending(parseTerranexBackup(await file.text()));
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'تعذر قراءة ملف النسخة الاحتياطية.');
    } finally {
      if (inputRef.current) inputRef.current.value = '';
    }
  }

  function applyRestore() {
    if (!pending) return;
    const confirmed = window.confirm(ar
      ? 'سيتم استبدال بيانات Terranex الحالية بالنسخة المختارة. هل تريد المتابعة؟'
      : 'Current Terranex data will be replaced. Continue?');
    if (!confirmed) return;

    try {
      downloadBackup(createTerranexBackup(), 'terranex-pre-restore');
      restoreTerranexBackup(pending);
      window.location.reload();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'تعذر استعادة النسخة الاحتياطية.');
    }
  }

  function clearData() {
    resetMessage();
    const first = window.confirm(ar
      ? 'سيتم حذف جميع بيانات Terranex المحلية من هذا المتصفح. هل تريد المتابعة؟'
      : 'All local Terranex data will be deleted from this browser. Continue?');
    if (!first) return;
    const second = window.confirm(ar
      ? 'تأكيد أخير: لا يمكن التراجع عن المسح إلا باستخدام نسخة احتياطية. هل تريد الحذف؟'
      : 'Final confirmation: deletion can only be reversed with a backup. Delete now?');
    if (!second) return;

    downloadBackup(createTerranexBackup(), 'terranex-pre-clear');
    clearTerranexData();
    window.location.reload();
  }

  return (
    <Card className="xl:col-span-3">
      <CardContent>
        <h3 className="mb-2 text-lg font-bold">{ar ? 'النسخ الاحتياطي والاستعادة' : 'Backup & Restore'}</h3>
        <p className="mb-4 text-sm leading-7 text-muted-foreground">
          {ar
            ? 'احفظ نسخة محلية من بيانات Terranex أو استعد نسخة سابقة بأمان. يتم تنزيل نسخة أمان تلقائيًا قبل الاستعادة أو المسح.'
            : 'Export local Terranex data or safely restore a previous backup. A safety copy is downloaded before restore or clear actions.'}
        </p>

        <div className="flex flex-wrap gap-2">
          <Button type="button" variant="secondary" onClick={exportBackup}>
            <Download className="h-4 w-4" />
            {ar ? 'تصدير نسخة احتياطية' : 'Export backup'}
          </Button>
          <Button type="button" variant="secondary" onClick={() => inputRef.current?.click()}>
            <Upload className="h-4 w-4" />
            {ar ? 'اختيار ملف للاستعادة' : 'Choose restore file'}
          </Button>
          <input
            ref={inputRef}
            type="file"
            accept="application/json,.json"
            className="hidden"
            onChange={(event) => void selectBackup(event.target.files?.[0])}
          />
        </div>

        {summary && (
          <div className="mt-4 rounded-xl border border-border bg-muted p-4 text-sm">
            <p className="font-bold">{ar ? 'ملخص النسخة المختارة' : 'Selected backup summary'}</p>
            <p className="mt-1 text-muted-foreground">
              {ar ? `${summary.keys} مفاتيح تخزين و${summary.records} سجلات ضمن المجموعات.` : `${summary.keys} storage keys and ${summary.records} collection records.`}
            </p>
            <Button type="button" className="mt-3" onClick={applyRestore}>
              {ar ? 'استعادة النسخة المختارة' : 'Restore selected backup'}
            </Button>
          </div>
        )}

        {message && <p className="mt-3 text-sm text-success">{message}</p>}
        {error && <p className="mt-3 text-sm text-danger">{error}</p>}

        <div className="mt-6 rounded-xl border border-danger/30 bg-danger/5 p-4">
          <h4 className="font-bold text-danger">{ar ? 'منطقة خطرة' : 'Danger zone'}</h4>
          <p className="mt-1 text-sm leading-6 text-muted-foreground">
            {ar ? 'استخدم المسح فقط عند الحاجة إلى بدء نسخة محلية فارغة.' : 'Clear data only when you need to start with an empty local workspace.'}
          </p>
          <Button type="button" variant="danger" className="mt-3" onClick={clearData}>
            <Trash2 className="h-4 w-4" />
            {ar ? 'مسح بيانات Terranex المحلية' : 'Clear local Terranex data'}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}

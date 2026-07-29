import { DatabaseBackup, Download, RotateCcw, Trash2 } from 'lucide-react';
import { Button } from '../../components/ui/Button';
import { Card, CardContent } from '../../components/ui/Card';
import type { Locale } from '../../core/types';
import { BACKUP_COVERAGE } from '../governance/dataHealth';

export function BackupRestoreSection({ locale }: { locale: Locale }) {
  const ar = locale === 'ar';
  return (
    <Card className="xl:col-span-3">
      <CardContent>
        <div className="flex items-start gap-3">
          <DatabaseBackup className="mt-1 h-5 w-5 text-warning" />
          <div>
            <h3 className="text-lg font-bold">{ar ? 'حدود النسخ الاحتياطي الحالية' : 'Current backup boundary'}</h3>
            <p className="mt-2 text-sm leading-7 text-muted-foreground">
              {ar
                ? 'الحزمة الموجودة في المتصفح تغطي المفاتيح والملفات المحلية فقط. لا تشمل صفوف بيانات العمل المحفوظة في Supabase، ولذلك لا يمكن تقديمها كنسخة كاملة أو استخدامها لاستعادة مساحة العمل بأمان.'
                : 'The browser archive covers local keys and uploaded files only. It does not include Supabase domain rows, so it cannot be presented as a complete backup or safely restore the workspace.'}
            </p>
          </div>
        </div>

        <dl className="mt-4 grid gap-2 text-sm sm:grid-cols-2">
          <div className="rounded-xl border p-3"><dt className="text-muted-foreground">{ar ? 'ملفات المتصفح المحلية' : 'Local browser files'}</dt><dd className="font-bold text-success">{BACKUP_COVERAGE.localUploadedFiles ? (ar ? 'مشمولة' : 'Covered') : '—'}</dd></div>
          <div className="rounded-xl border p-3"><dt className="text-muted-foreground">{ar ? 'صفوف Supabase' : 'Supabase rows'}</dt><dd className="font-bold text-danger">{BACKUP_COVERAGE.supabaseDomainRows ? (ar ? 'مشمولة' : 'Covered') : (ar ? 'غير مشمولة' : 'Not covered')}</dd></div>
        </dl>

        <div className="mt-4 flex flex-wrap gap-2" aria-describedby="backup-unavailable-reason">
          <Button variant="secondary" disabled><Download className="h-4 w-4" />{ar ? 'تصدير نسخة كاملة' : 'Export complete backup'}</Button>
          <Button variant="secondary" disabled><RotateCcw className="h-4 w-4" />{ar ? 'استعادة كاملة' : 'Complete restore'}</Button>
          <Button variant="danger" disabled><Trash2 className="h-4 w-4" />{ar ? 'مسح مساحة العمل' : 'Clear workspace'}</Button>
        </div>
        <p id="backup-unavailable-reason" className="mt-3 rounded-xl border border-warning/30 bg-warning/5 p-3 text-sm">
          {ar
            ? 'هذه الإجراءات متوقفة حتى إضافة خدمة خلفية تجمع بيانات Supabase والملفات في نسخة واحدة قابلة للتحقق والاستعادة.'
            : 'These actions remain disabled until a backend job can export and verify Supabase rows and files as one restorable archive.'}
        </p>
      </CardContent>
    </Card>
  );
}

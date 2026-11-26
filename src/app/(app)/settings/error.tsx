'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function SettingsError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="الإعدادات"
      detail="حدث خطأ أثناء تحميل الإعدادات. الصفحة للقراءة فقط."
      reset={reset}
      backHref="/"
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

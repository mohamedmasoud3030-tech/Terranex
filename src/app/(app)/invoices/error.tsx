'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function InvoicesError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="الفواتير"
      detail="حدث خطأ أثناء تحميل فواتير الموردين. الصفحة للقراءة فقط."
      reset={reset}
      backHref="/"
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

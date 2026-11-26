'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function DocumentsError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="المستندات"
      detail="حدث خطأ أثناء تحميل المستندات. الصفحة للقراءة فقط."
      reset={reset}
      backHref="/"
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

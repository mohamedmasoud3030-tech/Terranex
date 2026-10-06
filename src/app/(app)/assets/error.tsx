'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function AssetsError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="سجل الأصول"
      detail="حدث خطأ أثناء تحميل الأصول وأداء القطاعات. هذه الصفحة للقراءة فقط ولا تُجري أي كتابة."
      reset={reset}
      backHref="/"
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

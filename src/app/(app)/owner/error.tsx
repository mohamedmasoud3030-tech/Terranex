'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function OwnerError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="صفحات المالك"
      detail="حدث خطأ أثناء تحميل صفحات المالك. كل الصفحات دي للقراءة فقط باستثناء استيراد كشف الحساب."
      reset={reset}
      backHref="/"
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

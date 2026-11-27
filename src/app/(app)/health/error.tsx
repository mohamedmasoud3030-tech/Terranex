'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function HealthError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="فحص صحة الشركة"
      detail="حدث خطأ أثناء تحميل فحص الصحة. هذه الصفحة للقراءة فقط ولا تُجري أي كتابة."
      reset={reset}
      backHref="/"
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

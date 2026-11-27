'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function OwnerAskError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="اسأل أرقامك"
      detail="حدث خطأ أثناء حساب الإجابات. الصفحة للقراءة فقط."
      reset={reset}
      backHref="/owner"
      backLabel="العودة إلى الملخص الأسبوعي"
    />
  );
}

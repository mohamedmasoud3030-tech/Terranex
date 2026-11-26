'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function VatError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="الضريبة"
      detail="حدث خطأ أثناء تحميل المعالجات الضريبية. الصفحة للقراءة فقط."
      reset={reset}
      backHref="/"
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

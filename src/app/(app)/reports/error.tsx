'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function ReportsError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="التقارير"
      detail="حدث خطأ أثناء تحميل التقارير. الصفحة للقراءة فقط."
      reset={reset}
      backHref="/"
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function IntakeStartError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="مسار إدخال المشروع"
      detail="حدث خطأ أثناء قراءة خطوات الإدخال والأطراف ورأس المال."
      reset={reset}
      backHref={"/"}
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

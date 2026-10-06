'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function IntakeError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="مسار الإدخال"
      detail="حدث خطأ أثناء قراءة خطوات الإدخال والأطراف ورأس المال."
      reset={reset}
      backHref="/projects"
      backLabel="العودة إلى المشاريع"
    />
  );
}

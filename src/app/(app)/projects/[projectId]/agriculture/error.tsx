'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function AgricultureError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="مساحة الزراعة"
      detail="حدث خطأ أثناء قراءة بيانات الزراعة."
      reset={reset}
      backHref="/projects"
      backLabel="العودة إلى المشاريع"
    />
  );
}

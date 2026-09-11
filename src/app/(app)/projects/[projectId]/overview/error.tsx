'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function OverviewError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="نظرة عامة على المشروع"
      detail="حدث خطأ أثناء قراءة ملخص المركز المالي ومؤشرات القطاع."
      reset={reset}
      backHref={"/projects"}
      backLabel="العودة إلى المشاريع"
    />
  );
}

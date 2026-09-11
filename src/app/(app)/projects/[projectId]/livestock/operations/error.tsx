'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function LivestockOperationsError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="العمليات الحيوانية"
      detail="حدث خطأ أثناء قراءة العمليات الحيوانية."
      reset={reset}
      backHref="/projects"
      backLabel="العودة إلى المشاريع"
    />
  );
}

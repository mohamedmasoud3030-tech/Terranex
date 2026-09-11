'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function ProjectError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="مساحة المشروع"
      detail="حدث خطأ أثناء تحميل بيانات المشروع."
      reset={reset}
      backHref="/projects"
      backLabel="العودة إلى المشاريع"
    />
  );
}

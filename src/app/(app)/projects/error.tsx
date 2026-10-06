'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function ProjectsError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="سجل المشاريع"
      detail="حدث خطأ أثناء قراءة قائمة المشاريع وحالة كل مشروع."
      reset={reset}
      backHref={"/"}
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

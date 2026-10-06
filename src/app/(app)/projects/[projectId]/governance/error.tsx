'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function GovernanceError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="مساحة الحوكمة"
      detail="حدث خطأ أثناء قراءة سجل الصلاحيات والقرارات."
      reset={reset}
      backHref={"/projects"}
      backLabel="العودة إلى المشاريع"
    />
  );
}

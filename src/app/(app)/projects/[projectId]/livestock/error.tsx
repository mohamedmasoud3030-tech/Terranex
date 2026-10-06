'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function LivestockError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="مساحة الثروة الحيوانية"
      detail="حدث خطأ أثناء قراءة المواقع والقطعان والدفعات."
      reset={reset}
      backHref="/projects"
      backLabel="العودة إلى المشاريع"
    />
  );
}

'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function CloseError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="مساحة الإغلاق المالي"
      detail="حدث خطأ أثناء قراءة الفترات وبوابات الإغلاق واللقطات."
      reset={reset}
      backHref={"/projects"}
      backLabel="العودة إلى المشاريع"
    />
  );
}

'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function ControlsError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="سجل الضوابط والوقائع"
      detail="حدث خطأ أثناء قراءة أعضاء المنظمة وضوابط القطاع."
      reset={reset}
      backHref={"/projects"}
      backLabel="العودة إلى المشاريع"
    />
  );
}

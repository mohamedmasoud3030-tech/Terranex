'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function PilotError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="لوحة التشغيل التجريبي"
      detail="حدث خطأ أثناء قراءة مجاميع الرقابة وفروق المطابقة."
      reset={reset}
      backHref="/projects"
      backLabel="العودة إلى المشاريع"
    />
  );
}

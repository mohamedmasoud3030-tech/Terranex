'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function CashError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="مساحة النقدية"
      detail="حدث خطأ أثناء قراءة حركات النقدية والمطابقة البنكية."
      reset={reset}
      backHref={"/projects"}
      backLabel="العودة إلى المشاريع"
    />
  );
}

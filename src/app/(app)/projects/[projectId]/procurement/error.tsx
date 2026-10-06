'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function ProcurementError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="مساحة المشتريات"
      detail="حدث خطأ أثناء قراءة أوامر الشراء والفواتير والاستلام."
      reset={reset}
      backHref={"/projects"}
      backLabel="العودة إلى المشاريع"
    />
  );
}

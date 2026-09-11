'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function BudgetError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="مساحة الموازنة"
      detail="حدث خطأ أثناء قراءة بنود الموازنة والالتزام والفعلي."
      reset={reset}
      backHref={"/projects"}
      backLabel="العودة إلى المشاريع"
    />
  );
}

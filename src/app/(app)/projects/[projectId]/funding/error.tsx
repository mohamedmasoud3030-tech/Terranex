'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function FundingError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="مساحة التمويل"
      detail="حدث خطأ أثناء قراءة الالتزامات والمقبوضات."
      reset={reset}
      backHref={"/projects"}
      backLabel="العودة إلى المشاريع"
    />
  );
}

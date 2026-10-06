'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function IntegrityError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="مساحة سلامة السجل"
      detail="حدث خطأ أثناء قراءة فحوص السلامة والاستثناءات."
      reset={reset}
      backHref={"/projects"}
      backLabel="العودة إلى المشاريع"
    />
  );
}

'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function CostsError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="مساحة التكاليف"
      detail="حدث خطأ أثناء قراءة فئات التكلفة والقيود المُرحّلة."
      reset={reset}
      backHref={"/projects"}
      backLabel="العودة إلى المشاريع"
    />
  );
}

'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function OperationsError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="العمليات العقارية"
      detail="حدث خطأ أثناء قراءة الأصول والتصرفات والنتيجة المحققة."
      reset={reset}
      backHref="/projects"
      backLabel="العودة إلى المشاريع"
    />
  );
}

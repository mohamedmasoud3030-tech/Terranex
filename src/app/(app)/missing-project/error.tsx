'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function MissingProjectError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="مشروع غير موجود"
      detail="تعذر عرض الصفحة."
      reset={reset}
      backHref={"/"}
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

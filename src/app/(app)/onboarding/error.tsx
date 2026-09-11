'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function OnboardingError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="إنشاء المنظمة"
      detail="حدث خطأ أثناء قراءة بيانات المنظمة الحالية."
      reset={reset}
      backHref={"/"}
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function NewProjectError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="إنشاء مشروع"
      detail="حدث خطأ أثناء قراءة بيانات المنظمة المطلوبة للنموذج."
      reset={reset}
      backHref={"/"}
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

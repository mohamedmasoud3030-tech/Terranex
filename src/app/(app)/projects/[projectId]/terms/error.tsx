'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function TermsError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="مساحة شروط الاتفاقية"
      detail="حدث خطأ أثناء قراءة نسخ الاتفاقية وشروطها."
      reset={reset}
      backHref={"/projects"}
      backLabel="العودة إلى المشاريع"
    />
  );
}

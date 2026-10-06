'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function InvestorsError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="شفافية الأطراف والاتفاقية"
      detail="حدث خطأ أثناء قراءة الأطراف ونسخ الاتفاقية المعتمدة."
      reset={reset}
      backHref={"/projects"}
      backLabel="العودة إلى المشاريع"
    />
  );
}

'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function PortfolioError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="مساحة المحفظة"
      detail="حدث خطأ أثناء قراءة مشاريع المحفظة وأرصدة المشروع."
      reset={reset}
      backHref={"/portfolios"}
      backLabel="العودة إلى المحافظ"
    />
  );
}

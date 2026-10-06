'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function PortfoliosError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="سجل المحافظ"
      detail="حدث خطأ أثناء قراءة قائمة المحافظ ومشاريعها."
      reset={reset}
      backHref={"/portfolios"}
      backLabel="العودة إلى المحافظ"
    />
  );
}

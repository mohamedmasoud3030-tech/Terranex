'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function NewPortfolioError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="إنشاء محفظة"
      detail="حدث خطأ أثناء قراءة بيانات المنظمة المطلوبة للنموذج."
      reset={reset}
      backHref={"/portfolios"}
      backLabel="العودة إلى المحافظ"
    />
  );
}

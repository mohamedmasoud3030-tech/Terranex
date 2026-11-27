'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function OwnerBankImportError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="استيراد كشف البنك"
      detail="حدث خطأ أثناء تحميل صفحة الاستيراد. لم يتم تسجيل أي بيانات."
      reset={reset}
      backHref="/owner"
      backLabel="العودة إلى الملخص الأسبوعي"
    />
  );
}

'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function TransactionsError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="حركات البنك"
      detail="حدث خطأ أثناء تحميل حركات البنك. الصفحة للقراءة فقط."
      reset={reset}
      backHref="/"
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

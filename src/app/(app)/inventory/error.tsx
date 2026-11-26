'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function InventoryError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="المخزون"
      detail="حدث خطأ أثناء تحميل المخزون. الصفحة للقراءة فقط."
      reset={reset}
      backHref="/"
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

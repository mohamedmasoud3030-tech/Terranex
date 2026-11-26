'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function JournalError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="دفتر القيود"
      detail="حدث خطأ أثناء تحميل دفتر القيود. الصفحة للقراءة فقط."
      reset={reset}
      backHref="/"
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function PartiesError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="دليل الأطراف"
      detail="حدث خطأ أثناء تحميل دليل الأطراف. هذه الصفحة للقراءة فقط ولا تُجري أي كتابة."
      reset={reset}
      backHref="/"
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

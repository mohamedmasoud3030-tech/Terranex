'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function InviteError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="دعوة المنظمة"
      detail="حدث خطأ أثناء فتح رابط الدعوة. لم يُقبل أي انضمام."
      reset={reset}
      backHref="/"
      backLabel="العودة إلى اللوحة الرئيسية"
    />
  );
}

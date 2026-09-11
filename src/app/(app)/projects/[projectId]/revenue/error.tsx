'use client';

import { RouteError } from '@/shared/ui/route-error';

export default function RevenueError({ reset }: { reset: () => void }) {
  return (
    <RouteError
      surface="مساحة الإيراد"
      detail="حدث خطأ أثناء قراءة التصرفات والاعتراف والتحصيل."
      reset={reset}
      backHref={"/projects"}
      backLabel="العودة إلى المشاريع"
    />
  );
}

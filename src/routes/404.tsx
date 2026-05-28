import { createRoute } from '@tanstack/react-router';
import { rootRoute } from './__root';
import { useI18n } from '../core/i18n';

export const notFoundRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/404',
  component: NotFoundPage,
});

export function NotFoundPage() {
  const { locale } = useI18n();
  return (
    <div className="flex min-h-[60vh] flex-col items-center justify-center gap-6 text-center">
      <p className="text-8xl font-black text-muted">404</p>
      <h1 className="text-2xl font-bold">{locale === 'ar' ? 'الصفحة غير موجودة' : 'Page not found'}</h1>
      <p className="text-sm text-muted-foreground">{locale === 'ar' ? 'تحقق من الرابط أو عد إلى لوحة القيادة.' : 'Check the URL or return to the dashboard.'}</p>
      <a href="/dashboard" className="rounded-xl bg-primary px-6 py-3 text-sm font-semibold text-white transition hover:bg-primary/90">
        {locale === 'ar' ? 'العودة للوحة القيادة' : 'Back to Dashboard'}
      </a>
    </div>
  );
}

import './globals.css';
import type { Metadata } from 'next';
export const metadata: Metadata = { title: 'تيرانكس', description: 'نظام تشغيل الاستثمار' };
const THEME_BOOT =
  "try{var t=localStorage.getItem('tx-theme');if(t==='dark')document.documentElement.dataset.theme='dark'}catch(e){}";
export default function Layout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="ar" dir="rtl" suppressHydrationWarning><head><script dangerouslySetInnerHTML={{ __html: THEME_BOOT }} /></head><body>{children}</body></html>; }

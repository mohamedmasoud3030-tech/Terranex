import './globals.css';
import type { Metadata } from 'next';
export const metadata: Metadata = { title: 'تيرانكس', description: 'نظام تشغيل الاستثمار' };
export default function Layout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="ar" dir="rtl"><body>{children}</body></html>; }

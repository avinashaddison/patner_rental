import type { Metadata, Viewport } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';

const inter = Inter({
  subsets: ['latin'],
  variable: '--font-inter',
  display: 'swap',
});

export const metadata: Metadata = {
  title: 'Companion Ranchi — Admin',
  description:
    'Admin console for Companion Ranchi, a verified companionship marketplace (Ranchi). Social activities only — 18+, public places.',
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  themeColor: '#e60a4d',
  width: 'device-width',
  initialScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={inter.variable}>
      <body className="min-h-full bg-slate-50 font-sans text-slate-800">{children}</body>
    </html>
  );
}

'use client';

import { useState } from 'react';
import { Sidebar } from '@/components/Sidebar';
import { Topbar } from '@/components/Topbar';
import { LoadingState } from '@/components/ui/Spinner';
import { useAuthGuard } from '@/lib/auth';

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const { admin, loading } = useAuthGuard();
  const [mobileOpen, setMobileOpen] = useState(false);

  // While verifying the session, show a neutral splash (guard redirects on failure).
  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <LoadingState label="Loading console…" />
      </div>
    );
  }

  return (
    // App shell: full viewport height, only the main column scrolls — the
    // sidebar and topbar stay pinned.
    <div className="flex h-screen overflow-hidden">
      <Sidebar mobileOpen={mobileOpen} onClose={() => setMobileOpen(false)} />

      <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
        <Topbar admin={admin} onMenuClick={() => setMobileOpen(true)} />
        <main className="scrollbar-thin flex-1 overflow-y-auto px-4 py-6 lg:px-8 lg:py-8">
          <div className="w-full animate-fade-in">{children}</div>
        </main>
      </div>
    </div>
  );
}

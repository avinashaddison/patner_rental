'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { isAuthenticated } from '@/lib/auth';
import { LoadingState } from '@/components/ui/Spinner';

/** Entry route: bounce to the dashboard when signed in, otherwise to login. */
export default function IndexPage() {
  const router = useRouter();

  useEffect(() => {
    router.replace(isAuthenticated() ? '/dashboard' : '/login');
  }, [router]);

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-50">
      <LoadingState label="Redirecting…" />
    </div>
  );
}

'use client';

import { useEffect, useState, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import { HeartHandshake, Lock, Mail, ShieldCheck } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { isAuthenticated, login } from '@/lib/auth';
import { ApiError } from '@/lib/api';

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  // Already signed in → skip login.
  useEffect(() => {
    if (isAuthenticated()) router.replace('/dashboard');
  }, [router]);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      await login(email.trim(), password);
      router.replace('/dashboard');
    } catch (err) {
      if (err instanceof ApiError) {
        setError(
          err.status === 401 || err.code === 'UNAUTHORIZED'
            ? 'Invalid email or password.'
            : err.message,
        );
      } else {
        setError('Something went wrong. Please try again.');
      }
      setSubmitting(false);
    }
  }

  return (
    <main className="relative flex min-h-screen items-center justify-center overflow-hidden px-4 py-10">
      {/* Bold brutalist accent blocks */}
      <div className="pointer-events-none absolute -left-10 top-16 hidden h-28 w-28 rotate-12 border-2 border-ink bg-acid shadow-brutal-lg sm:block" />
      <div className="pointer-events-none absolute -right-8 bottom-20 hidden h-32 w-32 -rotate-6 border-2 border-ink bg-brand-500 shadow-brutal-lg sm:block" />
      <div className="pointer-events-none absolute right-24 top-10 hidden h-12 w-12 rotate-6 border-2 border-ink bg-sky-400 shadow-brutal sm:block" />

      <div className="relative w-full max-w-md">
        {/* Brand */}
        <div className="mb-8 flex flex-col items-center text-center">
          <span className="flex h-16 w-16 items-center justify-center rounded-md border-2 border-ink bg-brand-500 text-white shadow-brutal">
            <HeartHandshake className="h-8 w-8" />
          </span>
          <h1 className="mt-4 text-3xl font-black uppercase tracking-tight text-ink">
            Companion Ranchi
          </h1>
          <p className="mt-1 text-sm font-bold uppercase tracking-wider text-brand-600">
            Admin Console
          </p>
        </div>

        <div className="rounded-md border-2 border-ink bg-white p-6 shadow-brutal-lg sm:p-8">
          <div className="mb-6">
            <h2 className="text-lg font-extrabold text-ink">Sign in</h2>
            <p className="mt-1 text-sm text-slate-500">
              Use your admin credentials to access the console.
            </p>
          </div>

          <form onSubmit={onSubmit} className="space-y-4" noValidate>
            <Input
              label="Email"
              type="email"
              name="email"
              autoComplete="username"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="admin@companionranchi.com"
              leftIcon={<Mail className="h-4 w-4" />}
              disabled={submitting}
            />
            <Input
              label="Password"
              type="password"
              name="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
              leftIcon={<Lock className="h-4 w-4" />}
              disabled={submitting}
            />

            {error && (
              <div
                role="alert"
                className="rounded-md border-2 border-ink bg-red-500 px-3 py-2.5 text-sm font-bold text-white shadow-brutal-xs"
              >
                {error}
              </div>
            )}

            <Button
              type="submit"
              size="lg"
              className="w-full"
              loading={submitting}
              disabled={!email || !password}
            >
              Sign in
            </Button>
          </form>
        </div>

        <p className="mt-6 flex items-center justify-center gap-1.5 text-center text-xs text-slate-400">
          <ShieldCheck className="h-3.5 w-3.5" />
          Verified companionship marketplace · 18+ · public-place meetings only
        </p>
      </div>
    </main>
  );
}

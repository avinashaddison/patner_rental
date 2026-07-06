'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { ChevronDown, LogOut, Menu, ShieldCheck } from 'lucide-react';
import { logout, type AdminUser } from '@/lib/auth';
import { cn } from '@/lib/cn';

export interface TopbarProps {
  admin: AdminUser | null;
  onMenuClick: () => void;
}

function initials(name: string): string {
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase() ?? '')
    .join('');
}

const ROLE_LABEL: Record<string, string> = {
  SUPER_ADMIN: 'Super Admin',
  ADMIN: 'Admin',
  SUPPORT: 'Support',
  FINANCE: 'Finance',
};

export function Topbar({ admin, onMenuClick }: TopbarProps) {
  const router = useRouter();
  const [menuOpen, setMenuOpen] = useState(false);

  const handleLogout = () => {
    logout();
    router.replace('/login');
  };

  return (
    <header className="sticky top-0 z-20 flex h-16 items-center justify-between gap-4 border-b-2 border-ink bg-white px-4 lg:px-6">
      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={onMenuClick}
          className="rounded border-2 border-ink bg-white p-1.5 text-ink shadow-brutal-xs hover:bg-acid lg:hidden"
          aria-label="Open menu"
        >
          <Menu className="h-5 w-5" />
        </button>
        <div className="hidden items-center gap-2 rounded border-2 border-ink bg-lime-400 px-3 py-1 text-xs font-bold uppercase text-ink shadow-brutal-xs sm:flex">
          <ShieldCheck className="h-3.5 w-3.5" />
          Verified companionship marketplace
        </div>
      </div>

      <div className="relative">
        <button
          type="button"
          onClick={() => setMenuOpen((v) => !v)}
          className="flex items-center gap-2.5 rounded-md border-2 border-transparent px-2 py-1.5 transition-all hover:border-ink hover:bg-acid"
        >
          <span className="flex h-9 w-9 items-center justify-center rounded-md border-2 border-ink bg-brand-500 text-sm font-black text-white shadow-brutal-xs">
            {admin ? initials(admin.name) : '··'}
          </span>
          <span className="hidden text-left sm:block">
            <span className="block text-sm font-bold leading-tight text-ink">
              {admin?.name ?? 'Admin'}
            </span>
            <span className="block text-[11px] font-semibold uppercase leading-tight text-slate-500">
              {admin ? ROLE_LABEL[admin.role] ?? admin.role : ''}
            </span>
          </span>
          <ChevronDown
            className={cn(
              'h-4 w-4 text-ink transition-transform',
              menuOpen && 'rotate-180',
            )}
          />
        </button>

        {menuOpen && (
          <>
            <div className="fixed inset-0 z-10" onClick={() => setMenuOpen(false)} />
            <div className="absolute right-0 z-20 mt-2 w-56 animate-pop-in rounded-md border-2 border-ink bg-white p-1.5 shadow-brutal-lg">
              <div className="border-b-2 border-ink px-3 py-2">
                <p className="truncate text-sm font-bold text-ink">
                  {admin?.name ?? 'Admin'}
                </p>
                <p className="truncate text-xs font-medium text-slate-500">{admin?.email ?? ''}</p>
              </div>
              <button
                type="button"
                onClick={handleLogout}
                className="mt-1.5 flex w-full items-center gap-2 rounded border-2 border-ink bg-white px-3 py-2 text-sm font-bold text-ink shadow-brutal-xs transition-all hover:bg-red-500 hover:text-white active:translate-x-0.5 active:translate-y-0.5 active:shadow-none"
              >
                <LogOut className="h-4 w-4" />
                Log out
              </button>
            </div>
          </>
        )}
      </div>
    </header>
  );
}

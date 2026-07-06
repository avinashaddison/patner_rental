'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import {
  BarChart3,
  CalendarClock,
  CreditCard,
  Flag,
  HeartHandshake,
  Image as ImageIcon,
  LayoutDashboard,
  LifeBuoy,
  Settings,
  ShieldCheck,
  Tags,
  Users,
  Wallet,
  X,
  type LucideIcon,
} from 'lucide-react';
import { cn } from '@/lib/cn';

interface NavItem {
  label: string;
  href: string;
  icon: LucideIcon;
}

interface NavGroup {
  section: string;
  items: NavItem[];
}

/**
 * Sidebar links grouped by area. Feature agents add pages under
 * src/app/(dashboard)/<name>/page.tsx and wire them into a group here.
 */
const NAV_GROUPS: NavGroup[] = [
  {
    section: 'Overview',
    items: [
      { label: 'Dashboard', href: '/dashboard', icon: LayoutDashboard },
      { label: 'Analytics', href: '/analytics', icon: BarChart3 },
    ],
  },
  {
    section: 'Marketplace',
    items: [
      { label: 'Companions', href: '/companions', icon: HeartHandshake },
      { label: 'Categories', href: '/categories', icon: Tags },
      { label: 'Bookings', href: '/bookings', icon: CalendarClock },
      { label: 'Posts', href: '/posts', icon: ImageIcon },
      { label: 'Users', href: '/users', icon: Users },
    ],
  },
  {
    section: 'Trust & Safety',
    items: [
      { label: 'KYC', href: '/kyc', icon: ShieldCheck },
      { label: 'Complaints', href: '/complaints', icon: Flag },
      { label: 'Support', href: '/support', icon: LifeBuoy },
    ],
  },
  {
    section: 'Finance',
    items: [
      { label: 'Payments', href: '/payments', icon: CreditCard },
      { label: 'Payouts', href: '/payouts', icon: Wallet },
    ],
  },
  {
    section: 'System',
    items: [{ label: 'Settings', href: '/settings', icon: Settings }],
  },
];

function isActive(pathname: string, href: string): boolean {
  return pathname === href || pathname.startsWith(`${href}/`);
}

export interface SidebarProps {
  /** Mobile drawer open state (desktop sidebar is always visible). */
  mobileOpen: boolean;
  onClose: () => void;
}

export function Sidebar({ mobileOpen, onClose }: SidebarProps) {
  const pathname = usePathname();

  return (
    <>
      {/* Mobile backdrop */}
      {mobileOpen && (
        <div className="fixed inset-0 z-30 bg-ink/40 lg:hidden" onClick={onClose} />
      )}

      <aside
        className={cn(
          'fixed inset-y-0 left-0 z-40 flex w-[264px] flex-col border-r-2 border-ink bg-white transition-transform duration-200 lg:static lg:translate-x-0',
          mobileOpen ? 'translate-x-0' : '-translate-x-full',
        )}
      >
        {/* Brand */}
        <div className="flex h-16 items-center justify-between border-b-2 border-ink px-4">
          <Link href="/dashboard" className="flex items-center gap-2.5" onClick={onClose}>
            <span className="flex h-10 w-10 items-center justify-center rounded-md border-2 border-ink bg-brand-500 text-white shadow-brutal-xs">
              <HeartHandshake className="h-5 w-5" />
            </span>
            <span className="leading-tight">
              <span className="block text-sm font-black uppercase text-ink">Companion Ranchi</span>
              <span className="block text-[11px] font-bold uppercase tracking-wider text-brand-600">
                Admin Console
              </span>
            </span>
          </Link>
          <button
            type="button"
            onClick={onClose}
            className="rounded border-2 border-ink bg-white p-1 text-ink shadow-brutal-xs hover:bg-acid lg:hidden"
            aria-label="Close menu"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Nav */}
        <nav className="scrollbar-thin flex-1 space-y-5 overflow-y-auto px-3 py-4">
          {NAV_GROUPS.map((group) => (
            <div key={group.section}>
              <p className="mb-1.5 flex items-center gap-2 px-2 text-[10px] font-black uppercase tracking-[0.14em] text-ink/50">
                <span className="h-2 w-2 shrink-0 border border-ink bg-acid" />
                {group.section}
              </p>
              <div className="space-y-1.5">
                {group.items.map((item) => {
                  const active = isActive(pathname, item.href);
                  const Icon = item.icon;
                  return (
                    <Link
                      key={item.href}
                      href={item.href}
                      onClick={onClose}
                      className={cn(
                        'group flex items-center gap-3 rounded-md border-2 px-3 py-2 text-sm font-bold transition-all duration-100',
                        active
                          ? 'border-ink bg-brand-500 text-white shadow-brutal-sm'
                          : 'border-transparent text-ink hover:-translate-x-0.5 hover:-translate-y-0.5 hover:border-ink hover:bg-acid hover:shadow-brutal-xs',
                      )}
                    >
                      <Icon
                        className={cn(
                          'h-[18px] w-[18px] shrink-0',
                          active ? 'text-white' : 'text-ink',
                        )}
                      />
                      <span>{item.label}</span>
                    </Link>
                  );
                })}
              </div>
            </div>
          ))}
        </nav>

        {/* Safety footer — companionship marketplace guardrails */}
        <div className="border-t-2 border-ink p-3">
          <div className="rounded-md border-2 border-ink bg-acid px-3 py-2.5 shadow-brutal-xs">
            <p className="flex items-center gap-1.5 text-[11px] font-black uppercase text-ink">
              <ShieldCheck className="h-3.5 w-3.5" />
              Safety first
            </p>
            <p className="mt-1 text-[11px] font-semibold leading-snug text-ink/70">
              18+ only · public-place meetings · companionship activities only.
            </p>
          </div>
        </div>
      </aside>
    </>
  );
}

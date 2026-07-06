'use client';

import { useMemo, useState } from 'react';
import Link from 'next/link';
import useSWR from 'swr';
import {
  ArrowRight,
  CalendarCheck,
  Flag,
  HeartHandshake,
  IndianRupee,
  LifeBuoy,
  ShieldCheck,
  TrendingUp,
  UserPlus,
  Users,
  Wallet,
} from 'lucide-react';
import type { ReactNode } from 'react';
import { PageHeader } from '@/components/ui/PageHeader';
import { StatCard } from '@/components/ui/StatCard';
import { Card, CardHeader } from '@/components/ui/Card';
import { Select } from '@/components/ui/Select';
import { Badge } from '@/components/ui/Badge';
import { LoadingState } from '@/components/ui/Spinner';
import { RevenueChart, type RevenuePoint } from '@/components/RevenueChart';
import { swrFetcher } from '@/lib/api';
import { formatINR, formatNumber } from '@/lib/format';

/** Shape of `GET /admin/dashboard` (API.md §ADMIN). Extra fields are tolerated. */
interface DashboardStats {
  revenue: number;
  totalUsers: number;
  activeBookings: number;
  newRegistrations: number;
  totalCompanions?: number;
  pendingKyc?: number;
  pendingCompanions?: number;
  openComplaints?: number;
  revenueDelta?: number;
  usersDelta?: number;
  bookingsDelta?: number;
  registrationsDelta?: number;
}

/**
 * `GET /admin/analytics/revenue?period=...` returns a time series. We accept the common
 * envelope shapes: an array directly, or `{ series: [...] }`, with point fields normalized.
 */
interface RawRevenuePoint {
  label?: string;
  period?: string;
  date?: string;
  month?: string;
  revenue?: number;
  total?: number;
  amount?: number;
  commission?: number;
}
type RevenueResponse = RawRevenuePoint[] | { series?: RawRevenuePoint[]; data?: RawRevenuePoint[] };

type Period = 'daily' | 'weekly' | 'monthly' | 'yearly';

const PERIOD_OPTIONS = [
  { label: 'Daily', value: 'daily' },
  { label: 'Weekly', value: 'weekly' },
  { label: 'Monthly', value: 'monthly' },
  { label: 'Yearly', value: 'yearly' },
];

function normalizeRevenue(res: RevenueResponse | undefined): RevenuePoint[] {
  if (!res) return [];
  const arr: RawRevenuePoint[] = Array.isArray(res)
    ? res
    : res.series ?? res.data ?? [];
  return arr.map((p, i) => ({
    label: p.label ?? p.month ?? p.date ?? p.period ?? String(i + 1),
    revenue: Number(p.revenue ?? p.total ?? p.amount ?? 0) || 0,
    commission: p.commission !== undefined ? Number(p.commission) || 0 : undefined,
  }));
}

export default function DashboardPage() {
  const [period, setPeriod] = useState<Period>('monthly');

  const {
    data: stats,
    isLoading: statsLoading,
    error: statsError,
  } = useSWR<DashboardStats>('/dashboard', swrFetcher, { revalidateOnFocus: false });

  const { data: revenueRaw, isLoading: revenueLoading } = useSWR<RevenueResponse>(
    `/analytics/revenue?period=${period}`,
    swrFetcher,
    { revalidateOnFocus: false },
  );

  const revenueSeries = useMemo(() => normalizeRevenue(revenueRaw), [revenueRaw]);
  const periodTotal = useMemo(
    () => revenueSeries.reduce((sum, p) => sum + p.revenue, 0),
    [revenueSeries],
  );

  return (
    <div>
      <PageHeader
        eyebrow="Overview"
        title="Dashboard"
        description="Platform health for the Companion Ranchi marketplace — revenue, users and live bookings."
      />

      {statsError ? (
        <Card className="bg-red-50">
          <p className="text-sm font-semibold text-red-700">
            Couldn’t load dashboard stats. {(statsError as Error)?.message}
          </p>
        </Card>
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <StatCard
            label="Revenue"
            value={formatINR(stats?.revenue)}
            icon={<IndianRupee className="h-5 w-5" />}
            tone="brand"
            delta={stats?.revenueDelta}
            loading={statsLoading}
          />
          <StatCard
            label="Total Users"
            value={formatNumber(stats?.totalUsers)}
            icon={<Users className="h-5 w-5" />}
            tone="sky"
            delta={stats?.usersDelta}
            loading={statsLoading}
          />
          <StatCard
            label="Active Bookings"
            value={formatNumber(stats?.activeBookings)}
            icon={<CalendarCheck className="h-5 w-5" />}
            tone="emerald"
            delta={stats?.bookingsDelta}
            loading={statsLoading}
          />
          <StatCard
            label="New Registrations"
            value={formatNumber(stats?.newRegistrations)}
            icon={<UserPlus className="h-5 w-5" />}
            tone="amber"
            delta={stats?.registrationsDelta}
            loading={statsLoading}
          />
        </div>
      )}

      {/* Action center — fast jumps into the queues that need an admin. */}
      <div className="mt-7">
        <h2 className="mb-3 flex items-center gap-2 text-xs font-black uppercase tracking-[0.14em] text-ink">
          <span className="h-3 w-3 border-2 border-ink bg-acid" />
          Action center
        </h2>
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
          <QuickAction
            href="/kyc"
            label="Review KYC"
            icon={<ShieldCheck className="h-5 w-5" />}
            count={stats?.pendingKyc}
            tone="bg-acid text-ink"
          />
          <QuickAction
            href="/companions"
            label="Approve companions"
            icon={<HeartHandshake className="h-5 w-5" />}
            count={stats?.pendingCompanions}
            tone="bg-brand-500 text-white"
          />
          <QuickAction
            href="/complaints"
            label="Complaints"
            icon={<Flag className="h-5 w-5" />}
            count={stats?.openComplaints}
            tone="bg-red-500 text-white"
          />
          <QuickAction
            href="/support"
            label="Support inbox"
            icon={<LifeBuoy className="h-5 w-5" />}
            tone="bg-sky-400 text-ink"
          />
          <QuickAction
            href="/payouts"
            label="Process payouts"
            icon={<Wallet className="h-5 w-5" />}
            tone="bg-lime-400 text-ink"
          />
        </div>
      </div>

      {/* Revenue chart */}
      <Card className="mt-7">
        <CardHeader
          title="Revenue"
          subtitle={
            revenueLoading
              ? 'Loading…'
              : `${formatINR(periodTotal)} across the selected ${period} period`
          }
          action={
            <div className="flex items-center gap-2">
              <span className="hidden items-center gap-1 text-xs font-medium text-emerald-600 sm:flex">
                <TrendingUp className="h-3.5 w-3.5" />
                INR
              </span>
              <Select
                aria-label="Revenue period"
                value={period}
                onChange={(e) => setPeriod(e.target.value as Period)}
                options={PERIOD_OPTIONS}
                className="h-9 w-36"
              />
            </div>
          }
        />
        {revenueLoading ? (
          <LoadingState label="Loading revenue…" />
        ) : revenueSeries.length === 0 ? (
          <div className="flex h-[300px] items-center justify-center text-sm text-slate-400">
            No revenue data for this period yet.
          </div>
        ) : (
          <RevenueChart data={revenueSeries} />
        )}
      </Card>

      {/* Secondary operational snapshot — only renders fields the API provides */}
      {(stats?.pendingKyc !== undefined ||
        stats?.pendingCompanions !== undefined ||
        stats?.openComplaints !== undefined ||
        stats?.totalCompanions !== undefined) && (
        <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {stats?.totalCompanions !== undefined && (
            <SnapshotTile label="Companions" value={formatNumber(stats.totalCompanions)} />
          )}
          {stats?.pendingCompanions !== undefined && (
            <SnapshotTile
              label="Pending approvals"
              value={formatNumber(stats.pendingCompanions)}
              badge={stats.pendingCompanions > 0 ? 'amber' : 'green'}
            />
          )}
          {stats?.pendingKyc !== undefined && (
            <SnapshotTile
              label="KYC in queue"
              value={formatNumber(stats.pendingKyc)}
              badge={stats.pendingKyc > 0 ? 'amber' : 'green'}
            />
          )}
          {stats?.openComplaints !== undefined && (
            <SnapshotTile
              label="Open complaints"
              value={formatNumber(stats.openComplaints)}
              badge={stats.openComplaints > 0 ? 'red' : 'green'}
            />
          )}
        </div>
      )}
    </div>
  );
}

function SnapshotTile({
  label,
  value,
  badge,
}: {
  label: string;
  value: string;
  badge?: 'amber' | 'green' | 'red';
}) {
  return (
    <Card className="flex items-center justify-between">
      <div>
        <p className="text-xs font-bold uppercase tracking-wide text-slate-500">{label}</p>
        <p className="mt-1 text-2xl font-black text-ink">{value}</p>
      </div>
      {badge && <Badge tone={badge} dot>{badge === 'green' ? 'Clear' : 'Action'}</Badge>}
    </Card>
  );
}

/** A claymorphism quick-action tile linking to an admin queue. */
function QuickAction({
  href,
  label,
  icon,
  count,
  tone,
}: {
  href: string;
  label: string;
  icon: ReactNode;
  count?: number;
  /** Tailwind gradient stops, e.g. "from-amber-400 to-orange-500". */
  tone: string;
}) {
  const hasCount = typeof count === 'number';
  const c = count ?? 0;
  const urgent = hasCount && c > 0;
  return (
    <Link
      href={href}
      className="group flex flex-col gap-3 rounded-md border-2 border-ink bg-white p-4 shadow-brutal transition-all duration-100 hover:-translate-x-0.5 hover:-translate-y-0.5 hover:shadow-brutal-md active:translate-x-0 active:translate-y-0 active:shadow-brutal-xs"
    >
      <div className="flex items-center justify-between">
        <span
          className={`flex h-11 w-11 items-center justify-center rounded-md border-2 border-ink shadow-brutal-xs ${tone}`}
        >
          {icon}
        </span>
        {urgent && (
          <span className="inline-flex min-w-[26px] items-center justify-center rounded border-2 border-ink bg-red-500 px-1.5 py-0.5 text-xs font-black text-white shadow-brutal-xs">
            {c > 99 ? '99+' : c}
          </span>
        )}
      </div>
      <div>
        <p className="text-sm font-extrabold text-ink">{label}</p>
        <p className="mt-0.5 flex items-center gap-1 text-xs font-bold uppercase text-slate-500">
          {urgent ? `${c} waiting` : hasCount ? 'All clear' : 'Open'}
          <ArrowRight className="h-3 w-3 transition-transform group-hover:translate-x-0.5" />
        </p>
      </div>
    </Link>
  );
}

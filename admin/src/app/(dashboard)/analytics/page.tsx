'use client';

/**
 * Admin → Analytics
 *
 * Business intelligence for the companionship marketplace: headline KPIs plus a
 * revenue time-series that can be sliced daily / weekly / monthly / yearly. Commission
 * is the platform's actual earnings, so it is charted alongside gross revenue.
 *
 * Backed by (docs/API.md → ADMIN API):
 *   GET /admin/analytics/overview                          (KPI cards)
 *   GET /admin/analytics/revenue?period=daily|weekly|monthly|yearly   (time series)
 */

import { useMemo, useState } from 'react';
import useSWR from 'swr';
import {
  Area,
  AreaChart,
  CartesianGrid,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import {
  CalendarCheck,
  CheckCircle2,
  HeartHandshake,
  IndianRupee,
  Percent,
  Star,
  TrendingUp,
  Users,
} from 'lucide-react';
import { PageHeader } from '@/components/ui/PageHeader';
import { StatCard } from '@/components/ui/StatCard';
import { Card, CardHeader } from '@/components/ui/Card';
import { Select } from '@/components/ui/Select';
import { LoadingState } from '@/components/ui/Spinner';
import { swrFetcher } from '@/lib/api';
import { formatINR, formatINRCompact, formatNumber } from '@/lib/format';
import type { AnalyticsOverview } from '@/lib/types';

type Period = 'daily' | 'weekly' | 'monthly' | 'yearly';

const PERIOD_OPTIONS: { label: string; value: Period }[] = [
  { label: 'Daily', value: 'daily' },
  { label: 'Weekly', value: 'weekly' },
  { label: 'Monthly', value: 'monthly' },
  { label: 'Yearly', value: 'yearly' },
];

const PERIOD_NOUN: Record<Period, string> = {
  daily: 'day',
  weekly: 'week',
  monthly: 'month',
  yearly: 'year',
};

interface RevenuePoint {
  label: string;
  revenue: number;
  commission: number;
}

/** Tolerate the various field names the revenue endpoint may serialize. */
interface RawRevenuePoint {
  label?: string;
  period?: string;
  date?: string;
  day?: string;
  week?: string;
  month?: string;
  year?: string;
  revenue?: number;
  total?: number;
  amount?: number;
  gross?: number;
  commission?: number;
  platformEarnings?: number;
}
type RevenueResponse =
  | RawRevenuePoint[]
  | { series?: RawRevenuePoint[]; data?: RawRevenuePoint[]; points?: RawRevenuePoint[] };

function normalizeRevenue(res: RevenueResponse | undefined): RevenuePoint[] {
  if (!res) return [];
  const arr: RawRevenuePoint[] = Array.isArray(res)
    ? res
    : res.series ?? res.data ?? res.points ?? [];
  return arr.map((p, i) => ({
    label:
      p.label ?? p.day ?? p.date ?? p.week ?? p.month ?? p.year ?? p.period ?? String(i + 1),
    revenue: Number(p.revenue ?? p.total ?? p.amount ?? p.gross ?? 0) || 0,
    commission: Number(p.commission ?? p.platformEarnings ?? 0) || 0,
  }));
}

export default function AnalyticsPage() {
  const [period, setPeriod] = useState<Period>('monthly');

  const {
    data: overview,
    isLoading: overviewLoading,
    error: overviewError,
  } = useSWR<AnalyticsOverview>('/analytics/overview', swrFetcher, {
    revalidateOnFocus: false,
  });

  const { data: revenueRaw, isLoading: revenueLoading } = useSWR<RevenueResponse>(
    `/analytics/revenue?period=${period}`,
    swrFetcher,
    { revalidateOnFocus: false, keepPreviousData: true },
  );

  const series = useMemo(() => normalizeRevenue(revenueRaw), [revenueRaw]);

  const totals = useMemo(
    () =>
      series.reduce(
        (acc, p) => {
          acc.revenue += p.revenue;
          acc.commission += p.commission;
          return acc;
        },
        { revenue: 0, commission: 0 },
      ),
    [series],
  );

  const hasCommission = series.some((p) => p.commission > 0);

  return (
    <div>
      <PageHeader
        eyebrow="Insights"
        title="Analytics"
        description="Revenue, growth and engagement metrics for the Companion Ranchi marketplace."
      />

      {/* KPI cards */}
      {overviewError ? (
        <Card className="border-2 border-ink bg-rose-50/60">
          <p className="text-sm text-rose-700">
            Couldn&rsquo;t load analytics. {(overviewError as Error)?.message}
          </p>
        </Card>
      ) : (
        <>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <StatCard
              label="Total Revenue"
              value={formatINR(overview?.totalRevenue)}
              icon={<IndianRupee className="h-5 w-5" />}
              tone="brand"
              delta={overview?.revenueDelta}
              loading={overviewLoading}
            />
            <StatCard
              label="Platform Commission"
              value={formatINR(overview?.totalCommission)}
              icon={<Percent className="h-5 w-5" />}
              tone="emerald"
              loading={overviewLoading}
            />
            <StatCard
              label="Total Bookings"
              value={formatNumber(overview?.totalBookings)}
              icon={<CalendarCheck className="h-5 w-5" />}
              tone="sky"
              delta={overview?.bookingsDelta}
              loading={overviewLoading}
            />
            <StatCard
              label="Avg Booking Value"
              value={formatINR(overview?.avgBookingValue)}
              icon={<TrendingUp className="h-5 w-5" />}
              tone="amber"
              loading={overviewLoading}
            />
          </div>

          <div className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <StatCard
              label="Total Users"
              value={formatNumber(overview?.totalUsers)}
              icon={<Users className="h-5 w-5" />}
              tone="sky"
              delta={overview?.usersDelta}
              loading={overviewLoading}
            />
            <StatCard
              label="Active Companions"
              value={formatNumber(overview?.activeCompanions ?? overview?.totalCompanions)}
              icon={<HeartHandshake className="h-5 w-5" />}
              tone="brand"
              delta={overview?.companionsDelta}
              loading={overviewLoading}
            />
            <StatCard
              label="Completed Bookings"
              value={formatNumber(overview?.completedBookings)}
              icon={<CheckCircle2 className="h-5 w-5" />}
              tone="emerald"
              loading={overviewLoading}
            />
            <StatCard
              label="Avg Rating"
              value={
                overview?.avgRating !== undefined && overview.avgRating !== null
                  ? `${overview.avgRating.toFixed(1)} ★`
                  : '—'
              }
              icon={<Star className="h-5 w-5" />}
              tone="amber"
              loading={overviewLoading}
            />
          </div>
        </>
      )}

      {/* Revenue chart */}
      <Card className="mt-6">
        <CardHeader
          title="Revenue & commission"
          subtitle={
            revenueLoading
              ? 'Loading…'
              : `${formatINR(totals.revenue)} gross · ${formatINR(
                  totals.commission,
                )} commission across the selected ${PERIOD_NOUN[period]} range`
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
        {revenueLoading && series.length === 0 ? (
          <LoadingState label="Loading revenue…" />
        ) : series.length === 0 ? (
          <div className="flex h-[320px] items-center justify-center text-sm text-slate-400">
            No revenue data for this {PERIOD_NOUN[period]} range yet.
          </div>
        ) : (
          <RevenueCommissionChart data={series} showCommission={hasCommission} />
        )}
      </Card>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Revenue + commission area chart                                             */
/* -------------------------------------------------------------------------- */

function ChartTooltip({
  active,
  payload,
  label,
}: {
  active?: boolean;
  payload?: Array<{ value: number; name: string; color: string }>;
  label?: string;
}) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-md border-2 border-ink bg-white px-3 py-2 shadow-brutal">
      <p className="mb-1 text-xs font-medium text-slate-500">{label}</p>
      {payload.map((p) => (
        <p
          key={p.name}
          className="flex items-center gap-2 text-sm font-semibold text-slate-900"
        >
          <span className="h-2 w-2 rounded-full" style={{ background: p.color }} />
          <span className="text-slate-500">{p.name}:</span>
          {formatINR(p.value)}
        </p>
      ))}
    </div>
  );
}

function RevenueCommissionChart({
  data,
  showCommission,
}: {
  data: RevenuePoint[];
  showCommission: boolean;
}) {
  return (
    <ResponsiveContainer width="100%" height={320}>
      <AreaChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
        <defs>
          <linearGradient id="analyticsRevenue" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#fb2c63" stopOpacity={0.28} />
            <stop offset="100%" stopColor="#fb2c63" stopOpacity={0} />
          </linearGradient>
          <linearGradient id="analyticsCommission" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#059669" stopOpacity={0.22} />
            <stop offset="100%" stopColor="#059669" stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" stroke="#eef2f7" vertical={false} />
        <XAxis
          dataKey="label"
          tickLine={false}
          axisLine={false}
          tick={{ fontSize: 12, fill: '#94a3b8' }}
          dy={8}
        />
        <YAxis
          tickLine={false}
          axisLine={false}
          tick={{ fontSize: 12, fill: '#94a3b8' }}
          tickFormatter={(v) => formatINRCompact(v)}
          width={56}
        />
        <Tooltip content={<ChartTooltip />} cursor={{ stroke: '#ff97b5', strokeWidth: 1 }} />
        {showCommission && (
          <Legend
            verticalAlign="top"
            align="right"
            height={28}
            iconType="circle"
            wrapperStyle={{ fontSize: 12, color: '#64748b' }}
          />
        )}
        <Area
          type="monotone"
          dataKey="revenue"
          name="Revenue"
          stroke="#e60a4d"
          strokeWidth={2.5}
          fill="url(#analyticsRevenue)"
          activeDot={{ r: 5, strokeWidth: 0 }}
        />
        {showCommission && (
          <Area
            type="monotone"
            dataKey="commission"
            name="Commission"
            stroke="#059669"
            strokeWidth={2}
            fill="url(#analyticsCommission)"
            activeDot={{ r: 4, strokeWidth: 0 }}
          />
        )}
      </AreaChart>
    </ResponsiveContainer>
  );
}

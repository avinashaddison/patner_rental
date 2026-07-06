'use client';

/**
 * Admin → Payments
 *
 * Read-only payments ledger across the platform. Every row is a Razorpay
 * transaction tied to a booking. Filter by payment status, search by booking
 * code / Razorpay id / customer, and see captured / refunded totals at a glance.
 *
 * Backed by:
 *   GET /admin/payments?status=&q=&page=&limit=
 */

import { useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import useSWR from 'swr';
import { ArrowDownLeft, ArrowUpRight, CreditCard, Search, Wallet } from 'lucide-react';
import { PageHeader } from '@/components/ui/PageHeader';
import { Card } from '@/components/ui/Card';
import { StatCard } from '@/components/ui/StatCard';
import { Input } from '@/components/ui/Input';
import { Button } from '@/components/ui/Button';
import { Select } from '@/components/ui/Select';
import { StatusBadge } from '@/components/ui/Badge';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { apiFetchList } from '@/lib/api';
import { formatINR, formatDateTime } from '@/lib/format';
import type { AdminPayment } from '@/lib/types';

const PAGE_SIZE = 20;

const STATUS_OPTIONS = [
  { label: 'All statuses', value: '' },
  { label: 'Created', value: 'CREATED' },
  { label: 'Authorized', value: 'AUTHORIZED' },
  { label: 'Captured', value: 'CAPTURED' },
  { label: 'Failed', value: 'FAILED' },
  { label: 'Refunded', value: 'REFUNDED' },
];

/** Optional rollups the ledger endpoint may attach in `meta`. */
interface PaymentMeta {
  total?: number;
  totalCaptured?: number;
  totalRefunded?: number;
  netRevenue?: number;
}

interface PaymentListResponse {
  data: AdminPayment[];
  meta?: PaymentMeta;
}

export default function PaymentsPage() {
  const router = useRouter();
  const [status, setStatus] = useState('');
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(1);

  const swrKey = useMemo(() => {
    const p = new URLSearchParams();
    p.set('page', String(page));
    p.set('limit', String(PAGE_SIZE));
    if (status) p.set('status', status);
    if (query) p.set('q', query);
    return `/payments?${p.toString()}`;
  }, [status, query, page]);

  const { data, isLoading, error } = useSWR<PaymentListResponse>(
    swrKey,
    (path: string) =>
      apiFetchList<AdminPayment[]>(path).then((r) => ({
        data: r.data ?? [],
        meta: r.meta as PaymentMeta | undefined,
      })),
    { revalidateOnFocus: false, keepPreviousData: true },
  );

  const rows = data?.data ?? [];
  const meta = data?.meta;
  const total = meta?.total ?? rows.length;

  // Prefer server rollups; otherwise derive from the current page as a fallback.
  const capturedTotal =
    meta?.totalCaptured ??
    rows.filter((p) => p.status === 'CAPTURED').reduce((s, p) => s + (p.amount || 0), 0);
  const refundedTotal =
    meta?.totalRefunded ??
    rows.filter((p) => p.status === 'REFUNDED').reduce((s, p) => s + (p.amount || 0), 0);
  const netRevenue = meta?.netRevenue ?? capturedTotal - refundedTotal;
  const derived = meta?.totalCaptured === undefined;

  function submitSearch(e: React.FormEvent) {
    e.preventDefault();
    setPage(1);
    setQuery(search.trim());
  }

  const columns: Column<AdminPayment>[] = [
    {
      key: 'booking',
      header: 'Booking',
      render: (p) => (
        <div className="min-w-0">
          <p className="font-mono text-xs font-semibold text-slate-900">
            {p.booking?.bookingCode ?? '—'}
          </p>
          {p.booking?.activity && (
            <p className="truncate text-xs text-slate-500">{p.booking.activity}</p>
          )}
        </div>
      ),
    },
    {
      key: 'customer',
      header: 'Customer',
      hideOnMobile: true,
      render: (p) => (
        <div className="min-w-0">
          <p className="truncate font-medium text-slate-800">
            {p.customer?.fullName ?? p.booking?.customer?.fullName ?? 'Unknown'}
          </p>
          <p className="truncate text-xs text-slate-500">
            {p.customer?.mobileNumber ?? p.booking?.customer?.mobileNumber ?? '—'}
          </p>
        </div>
      ),
    },
    {
      key: 'razorpay',
      header: 'Razorpay',
      hideOnMobile: true,
      render: (p) => (
        <div className="min-w-0">
          <p className="truncate font-mono text-xs text-slate-700">
            {p.razorpayPaymentId ?? p.razorpayOrderId ?? '—'}
          </p>
          <p className="text-xs text-slate-400">{p.method ?? 'razorpay'}</p>
        </div>
      ),
    },
    {
      key: 'date',
      header: 'Date',
      hideOnMobile: true,
      render: (p) => (
        <span className="text-slate-500">
          {formatDateTime(p.capturedAt ?? p.createdAt)}
        </span>
      ),
    },
    {
      key: 'amount',
      header: 'Amount',
      align: 'right',
      render: (p) => (
        <span
          className={
            p.status === 'REFUNDED'
              ? 'font-medium text-rose-600'
              : 'font-medium text-slate-900'
          }
        >
          {p.status === 'REFUNDED' ? '− ' : ''}
          {formatINR(p.amount)}
        </span>
      ),
    },
    {
      key: 'status',
      header: 'Status',
      align: 'center',
      render: (p) => <StatusBadge status={p.status} />,
    },
  ];

  return (
    <div>
      <PageHeader
        eyebrow="Finance"
        title="Payments"
        description="Razorpay payments ledger for every booking. All amounts are in INR."
      />

      {/* Totals */}
      <div className="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-3">
        <StatCard
          label="Captured"
          value={formatINR(capturedTotal)}
          tone="emerald"
          icon={<ArrowDownLeft className="h-5 w-5" />}
          deltaLabel={derived ? 'this page' : 'all time'}
        />
        <StatCard
          label="Refunded"
          value={formatINR(refundedTotal)}
          tone="rose"
          icon={<ArrowUpRight className="h-5 w-5" />}
          deltaLabel={derived ? 'this page' : 'all time'}
        />
        <StatCard
          label="Net revenue"
          value={formatINR(netRevenue)}
          tone="brand"
          icon={<Wallet className="h-5 w-5" />}
          deltaLabel={derived ? 'this page' : 'all time'}
        />
      </div>

      {/* Filters */}
      <Card className="mb-4">
        <form onSubmit={submitSearch} className="flex flex-col gap-3 sm:flex-row sm:items-end">
          <Input
            label="Search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Booking code, Razorpay id or customer…"
            leftIcon={<Search className="h-4 w-4" />}
            containerClassName="flex-1"
          />
          <Select
            label="Status"
            value={status}
            onChange={(e) => {
              setStatus(e.target.value);
              setPage(1);
            }}
            options={STATUS_OPTIONS}
            containerClassName="w-full sm:w-52"
          />
          <Button type="submit" className="sm:w-auto">
            Search
          </Button>
        </form>
      </Card>

      {error ? (
        <Card className="border-rose-200 bg-rose-50/60">
          <p className="text-sm text-rose-700">
            Couldn’t load payments. {(error as Error)?.message}
          </p>
        </Card>
      ) : (
        <DataTable
          columns={columns}
          rows={rows}
          rowKey={(p) => p.id}
          loading={isLoading}
          emptyMessage="No payments match these filters."
          emptyIcon={<CreditCard className="h-8 w-8" />}
          onRowClick={(p) =>
            p.booking?.id || p.bookingId
              ? router.push(`/bookings/${p.booking?.id ?? p.bookingId}`)
              : undefined
          }
          pagination={{ page, limit: PAGE_SIZE, total, onPageChange: setPage }}
        />
      )}
    </div>
  );
}

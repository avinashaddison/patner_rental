'use client';

/**
 * Admin → Bookings
 *
 * Browse every companionship booking on the platform. Filter by status, search by
 * booking code / customer / companion, and cancel or refund directly from the row.
 * Bookings are social-activity meetings in public places only (coffee, movies,
 * shopping, events, city tours) — no adult services.
 *
 * Backed by:
 *   GET  /admin/bookings?status=&q=&page=&limit=
 *   POST /admin/bookings/:id/cancel   { reason }
 *   POST /admin/bookings/:id/refund   { amount? }
 */

import { useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import useSWR from 'swr';
import { CalendarClock, PlayCircle, RotateCcw, Search, XCircle } from 'lucide-react';
import { PageHeader } from '@/components/ui/PageHeader';
import { Card } from '@/components/ui/Card';
import { Input } from '@/components/ui/Input';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { Select } from '@/components/ui/Select';
import { StatusBadge } from '@/components/ui/Badge';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { apiFetch, apiFetchList, ApiError } from '@/lib/api';
import { formatINR, formatDate } from '@/lib/format';
import type { AdminBooking, BookingStatus } from '@/lib/types';

const PAGE_SIZE = 20;

const STATUS_OPTIONS = [
  { label: 'All statuses', value: '' },
  { label: 'Pending', value: 'PENDING' },
  { label: 'Confirmed', value: 'CONFIRMED' },
  { label: 'In progress', value: 'IN_PROGRESS' },
  { label: 'Completed', value: 'COMPLETED' },
  { label: 'Cancelled', value: 'CANCELLED' },
  { label: 'Refunded', value: 'REFUNDED' },
];

/** Statuses where the booking is still cancellable (pre-completion). */
const CANCELLABLE: BookingStatus[] = ['PENDING', 'CONFIRMED', 'IN_PROGRESS'];
/** Paid states that can still be refunded to the customer. */
const REFUNDABLE: BookingStatus[] = ['CONFIRMED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'];

interface BookingListResponse {
  data: AdminBooking[];
  meta?: { total: number };
}

type ActionKind = 'cancel' | 'refund' | 'start';

export default function BookingsPage() {
  const router = useRouter();
  const [status, setStatus] = useState('');
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(1);

  const [target, setTarget] = useState<AdminBooking | null>(null);
  const [action, setAction] = useState<ActionKind>('cancel');
  const [reason, setReason] = useState('');
  const [refundAmount, setRefundAmount] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [banner, setBanner] = useState<string | null>(null);

  const swrKey = useMemo(() => {
    const p = new URLSearchParams();
    p.set('page', String(page));
    p.set('limit', String(PAGE_SIZE));
    if (status) p.set('status', status);
    if (query) p.set('q', query);
    return `/bookings?${p.toString()}`;
  }, [status, query, page]);

  const { data, isLoading, error, mutate } = useSWR<BookingListResponse>(
    swrKey,
    (path: string) =>
      apiFetchList<AdminBooking[]>(path).then((r) => ({ data: r.data ?? [], meta: r.meta })),
    { revalidateOnFocus: false, keepPreviousData: true },
  );

  const rows = data?.data ?? [];
  const total = data?.meta?.total ?? rows.length;

  function submitSearch(e: React.FormEvent) {
    e.preventDefault();
    setPage(1);
    setQuery(search.trim());
  }

  function openAction(booking: AdminBooking, kind: ActionKind) {
    setTarget(booking);
    setAction(kind);
    setReason('');
    setRefundAmount(kind === 'refund' ? String(booking.totalAmount ?? '') : '');
    setActionError(null);
  }

  async function confirmAction() {
    if (!target) return;
    setSubmitting(true);
    setActionError(null);
    try {
      if (action === 'cancel') {
        const trimmed = reason.trim();
        if (!trimmed) {
          setActionError('A cancellation reason is required.');
          setSubmitting(false);
          return;
        }
        await apiFetch(`/bookings/${target.id}/cancel`, {
          method: 'POST',
          body: { reason: trimmed },
        });
        setBanner(`Booking ${target.bookingCode} cancelled.`);
      } else if (action === 'start') {
        await apiFetch(`/bookings/${target.id}/start`, { method: 'POST' });
        setBanner(`Booking ${target.bookingCode} started.`);
      } else {
        // Refund: amount optional — omit to refund the full captured amount.
        const body: { amount?: number } = {};
        const raw = refundAmount.trim();
        if (raw) {
          const amount = Number(raw);
          if (Number.isNaN(amount) || amount <= 0) {
            setActionError('Enter a valid refund amount, or leave blank for a full refund.');
            setSubmitting(false);
            return;
          }
          body.amount = amount;
        }
        await apiFetch(`/bookings/${target.id}/refund`, { method: 'POST', body });
        setBanner(`Refund issued for booking ${target.bookingCode}.`);
      }
      setTarget(null);
      await mutate();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Action failed.');
    } finally {
      setSubmitting(false);
    }
  }

  const columns: Column<AdminBooking>[] = [
    {
      key: 'code',
      header: 'Booking',
      render: (b) => (
        <div className="min-w-0">
          <p className="font-mono text-xs font-semibold text-slate-900">{b.bookingCode}</p>
          <p className="truncate text-xs text-slate-500">
            {b.activity} · {b.durationHours}h
          </p>
        </div>
      ),
    },
    {
      key: 'customer',
      header: 'Customer',
      hideOnMobile: true,
      render: (b) => (
        <PersonCell
          name={b.customer?.fullName}
          sub={b.customer?.mobileNumber}
          fallback="Unknown customer"
        />
      ),
    },
    {
      key: 'companion',
      header: 'Companion',
      hideOnMobile: true,
      render: (b) => (
        <PersonCell
          name={b.companion?.name ?? b.companion?.user?.fullName}
          sub={b.companion?.user?.mobileNumber}
          fallback="Unknown companion"
        />
      ),
    },
    {
      key: 'date',
      header: 'Date',
      hideOnMobile: true,
      render: (b) => (
        <div>
          <p className="text-slate-700">{formatDate(b.bookingDate)}</p>
          <p className="text-xs text-slate-400">{b.startTime}</p>
        </div>
      ),
    },
    {
      key: 'amount',
      header: 'Amount',
      align: 'right',
      render: (b) => (
        <span className="font-medium text-slate-900">{formatINR(b.totalAmount)}</span>
      ),
    },
    {
      key: 'status',
      header: 'Status',
      align: 'center',
      render: (b) => <StatusBadge status={b.status} />,
    },
    {
      key: 'actions',
      header: 'Actions',
      align: 'right',
      render: (b) => {
        const stop = (fn: () => void) => (e: React.MouseEvent) => {
          e.stopPropagation();
          fn();
        };
        const canCancel = CANCELLABLE.includes(b.status);
        const canRefund =
          REFUNDABLE.includes(b.status) && b.status !== 'REFUNDED' && Boolean(b.payment);
        const canStart = b.status === 'CONFIRMED';
        if (!canCancel && !canRefund && !canStart) {
          return <span className="text-xs text-slate-400">—</span>;
        }
        return (
          <div className="flex items-center justify-end gap-2">
            {canStart && (
              <Button
                size="sm"
                variant="primary"
                onClick={stop(() => openAction(b, 'start'))}
                leftIcon={<PlayCircle className="h-3.5 w-3.5" />}
              >
                Start
              </Button>
            )}
            {canCancel && (
              <Button
                size="sm"
                variant="outline"
                onClick={stop(() => openAction(b, 'cancel'))}
                leftIcon={<XCircle className="h-3.5 w-3.5" />}
              >
                Cancel
              </Button>
            )}
            {canRefund && (
              <Button
                size="sm"
                variant="danger"
                onClick={stop(() => openAction(b, 'refund'))}
                leftIcon={<RotateCcw className="h-3.5 w-3.5" />}
              >
                Refund
              </Button>
            )}
          </div>
        );
      },
    },
  ];

  return (
    <div>
      <PageHeader
        eyebrow="Operations"
        title="Bookings"
        description="Every companionship booking — coffee, movies, shopping, events and city tours in public places only."
      />

      {/* Filters */}
      <Card className="mb-4">
        <form onSubmit={submitSearch} className="flex flex-col gap-3 sm:flex-row sm:items-end">
          <Input
            label="Search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Booking code, customer or companion…"
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

      {banner && (
        <Card className="mb-4 border-2 border-ink bg-emerald-50/70">
          <div className="flex items-center justify-between gap-3">
            <p className="text-sm text-emerald-700">{banner}</p>
            <button
              type="button"
              onClick={() => setBanner(null)}
              className="text-xs font-medium text-emerald-600 hover:text-emerald-800"
            >
              Dismiss
            </button>
          </div>
        </Card>
      )}

      {actionError && !target && (
        <Card className="mb-4 border-2 border-ink bg-rose-50/70">
          <p className="text-sm text-rose-700">{actionError}</p>
        </Card>
      )}

      {error ? (
        <Card className="border-2 border-ink bg-rose-50/60">
          <p className="text-sm text-rose-700">
            Couldn’t load bookings. {(error as Error)?.message}
          </p>
        </Card>
      ) : (
        <DataTable
          columns={columns}
          rows={rows}
          rowKey={(b) => b.id}
          loading={isLoading}
          emptyMessage="No bookings match these filters."
          emptyIcon={<CalendarClock className="h-8 w-8" />}
          onRowClick={(b) => router.push(`/bookings/${b.id}`)}
          pagination={{ page, limit: PAGE_SIZE, total, onPageChange: setPage }}
        />
      )}

      {/* Cancel / refund modal */}
      <Modal
        open={Boolean(target)}
        onClose={() => (submitting ? null : setTarget(null))}
        dismissible={!submitting}
        title={
          action === 'cancel'
            ? 'Cancel booking'
            : action === 'start'
              ? 'Start booking'
              : 'Refund booking'
        }
        description={
          target
            ? action === 'cancel'
              ? `Cancel ${target.bookingCode}. If it was paid, the refund policy is applied automatically.`
              : action === 'start'
                ? `Force-start ${target.bookingCode} without the customer's start code. Use only when both parties have met.`
                : `Refund the payment for ${target.bookingCode} back to the customer.`
            : undefined
        }
        footer={
          <>
            <Button variant="ghost" onClick={() => setTarget(null)} disabled={submitting}>
              Close
            </Button>
            <Button
              variant={action === 'start' ? 'primary' : 'danger'}
              loading={submitting}
              onClick={confirmAction}
            >
              {action === 'cancel'
                ? 'Cancel booking'
                : action === 'start'
                  ? 'Start booking'
                  : 'Issue refund'}
            </Button>
          </>
        }
      >
        {action === 'cancel' ? (
          <>
            <label className="mb-1.5 block text-sm font-medium text-slate-700">Reason</label>
            <textarea
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              rows={3}
              autoFocus
              placeholder="e.g. Customer requested cancellation; companion unavailable."
              className="w-full rounded-md border-2 border-ink bg-white p-3 text-sm text-slate-900 transition-colors focus:ring-2 focus:ring-brand-500/50"
            />
          </>
        ) : action === 'start' ? (
          <div className="space-y-2 text-sm text-slate-600">
            <p>
              This moves the booking to <strong>In progress</strong> and records the
              start time now. Normally the companion enters the customer&apos;s
              6-digit code at the meeting point instead.
            </p>
            {target?.startCode && (
              <p className="rounded-md border-2 border-ink bg-white p-2.5">
                Customer start code:{' '}
                <span className="font-mono text-base font-bold tracking-widest text-brand-700">
                  {target.startCode}
                </span>
              </p>
            )}
          </div>
        ) : (
          <>
            <Input
              label="Refund amount (₹)"
              type="number"
              min={1}
              step="0.01"
              value={refundAmount}
              onChange={(e) => setRefundAmount(e.target.value)}
              hint={`Leave blank for a full refund${
                target ? ` of ${formatINR(target.totalAmount)}` : ''
              }.`}
              placeholder={target ? String(target.totalAmount) : 'Full amount'}
            />
          </>
        )}
        {actionError && target && <p className="mt-2 text-xs text-rose-600">{actionError}</p>}
      </Modal>
    </div>
  );
}

function PersonCell({
  name,
  sub,
  fallback,
}: {
  name?: string | null;
  sub?: string | null;
  fallback: string;
}) {
  return (
    <div className="min-w-0">
      <p className="truncate font-medium text-slate-800">{name || fallback}</p>
      {sub && <p className="truncate text-xs text-slate-500">{sub}</p>}
    </div>
  );
}

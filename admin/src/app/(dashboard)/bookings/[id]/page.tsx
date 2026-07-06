'use client';

/**
 * Admin → Booking detail
 *
 * Full booking record: parties, the social activity + public meeting place,
 * money breakdown (total / commission / companion payout), linked payment, and the
 * status-change timeline. Admin can cancel (pre-completion) or refund a paid booking.
 *
 * Backed by:
 *   GET  /admin/bookings/:id            (detail incl. statusHistory + payment)
 *   POST /admin/bookings/:id/cancel     { reason }
 *   POST /admin/bookings/:id/refund     { amount? }
 */

import { useState } from 'react';
import { useParams } from 'next/navigation';
import Link from 'next/link';
import useSWR from 'swr';
import {
  ArrowLeft,
  CalendarClock,
  Clock,
  IndianRupee,
  KeyRound,
  MapPin,
  PlayCircle,
  Receipt,
  RotateCcw,
  ShieldCheck,
  User,
  XCircle,
} from 'lucide-react';
import { PageHeader } from '@/components/ui/PageHeader';
import { Card, CardHeader } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { Input } from '@/components/ui/Input';
import { Badge, StatusBadge } from '@/components/ui/Badge';
import { LoadingState } from '@/components/ui/Spinner';
import { swrFetcher, apiFetch, ApiError } from '@/lib/api';
import { formatINR, formatDate, formatDateTime } from '@/lib/format';
import type { AdminBooking, BookingStatus } from '@/lib/types';

const CANCELLABLE: BookingStatus[] = ['PENDING', 'CONFIRMED', 'IN_PROGRESS'];
const REFUNDABLE: BookingStatus[] = ['CONFIRMED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'];

type ActionKind = 'cancel' | 'refund' | 'start';

export default function BookingDetailPage() {
  const params = useParams<{ id: string }>();
  const id = params?.id;

  const { data, isLoading, error, mutate } = useSWR<AdminBooking>(
    id ? `/bookings/${id}` : null,
    swrFetcher,
    { revalidateOnFocus: false },
  );

  const [action, setAction] = useState<ActionKind | null>(null);
  const [reason, setReason] = useState('');
  const [refundAmount, setRefundAmount] = useState('');
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  function openAction(kind: ActionKind) {
    setAction(kind);
    setReason('');
    setRefundAmount(kind === 'refund' && data ? String(data.totalAmount ?? '') : '');
    setActionError(null);
  }

  async function confirmAction() {
    if (!id || !action) return;
    setBusy(true);
    setActionError(null);
    try {
      if (action === 'cancel') {
        const trimmed = reason.trim();
        if (!trimmed) {
          setActionError('A cancellation reason is required.');
          setBusy(false);
          return;
        }
        await apiFetch(`/bookings/${id}/cancel`, { method: 'POST', body: { reason: trimmed } });
      } else if (action === 'start') {
        await apiFetch(`/bookings/${id}/start`, { method: 'POST' });
      } else {
        const body: { amount?: number } = {};
        const raw = refundAmount.trim();
        if (raw) {
          const amount = Number(raw);
          if (Number.isNaN(amount) || amount <= 0) {
            setActionError('Enter a valid refund amount, or leave blank for a full refund.');
            setBusy(false);
            return;
          }
          body.amount = amount;
        }
        await apiFetch(`/bookings/${id}/refund`, { method: 'POST', body });
      }
      setAction(null);
      await mutate();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Action failed.');
    } finally {
      setBusy(false);
    }
  }

  if (isLoading) return <LoadingState label="Loading booking…" />;

  if (error || !data) {
    return (
      <div>
        <BackLink />
        <Card className="border-2 border-ink bg-rose-50/60">
          <p className="text-sm text-rose-700">
            Couldn’t load this booking. {(error as Error)?.message ?? 'Not found.'}
          </p>
        </Card>
      </div>
    );
  }

  const b = data;
  const customerName = b.customer?.fullName ?? 'Unknown customer';
  const companionName = b.companion?.name ?? b.companion?.user?.fullName ?? 'Unknown companion';

  const canCancel = CANCELLABLE.includes(b.status);
  const canRefund = REFUNDABLE.includes(b.status) && b.status !== 'REFUNDED' && Boolean(b.payment);
  // Panel confirm: force-start a confirmed (paid) booking from the admin side.
  const canStart = b.status === 'CONFIRMED';

  // Money breakdown — fall back to the documented split when snapshots are absent.
  const total = b.totalAmount ?? 0;
  const commission =
    b.commissionAmount ??
    (b.commissionRate != null ? round2((total * b.commissionRate) / 100) : undefined);
  const payout = b.companionPayout ?? (commission != null ? round2(total - commission) : undefined);

  // Build the timeline from statusHistory, newest first.
  const history = [...(b.statusHistory ?? [])].sort(
    (a, c) => new Date(c.createdAt).getTime() - new Date(a.createdAt).getTime(),
  );

  return (
    <div>
      <BackLink />

      <PageHeader
        eyebrow="Booking"
        title={b.bookingCode}
        description={`${b.activity} · ${b.durationHours}h companionship`}
        actions={
          <div className="flex flex-wrap items-center gap-2">
            {canStart && (
              <Button
                variant="primary"
                onClick={() => openAction('start')}
                leftIcon={<PlayCircle className="h-4 w-4" />}
              >
                Start booking
              </Button>
            )}
            {canCancel && (
              <Button
                variant="outline"
                onClick={() => openAction('cancel')}
                leftIcon={<XCircle className="h-4 w-4" />}
              >
                Cancel
              </Button>
            )}
            {canRefund && (
              <Button
                variant="danger"
                onClick={() => openAction('refund')}
                leftIcon={<RotateCcw className="h-4 w-4" />}
              >
                Refund
              </Button>
            )}
          </div>
        }
      />

      {/* Status strip */}
      <div className="mb-6 flex flex-wrap items-center gap-2">
        <StatusBadge status={b.status} />
        {b.payment && <StatusBadge status={b.payment.status} />}
        <Badge tone="brand">
          <CalendarClock className="h-3 w-3" /> {formatDate(b.bookingDate)} · {b.startTime}
        </Badge>
      </div>

      {actionError && action === null && (
        <Card className="mb-4 border-2 border-ink bg-rose-50/70">
          <p className="text-sm text-rose-700">{actionError}</p>
        </Card>
      )}

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        {/* Left: details + payment */}
        <div className="space-y-6 lg:col-span-2">
          {/* Meeting */}
          <Card>
            <CardHeader title="Meeting details" subtitle="Public-place companionship only" />
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <InfoRow icon={<CalendarClock className="h-4 w-4" />} label="Activity" value={b.activity} />
              <InfoRow
                icon={<Clock className="h-4 w-4" />}
                label="When"
                value={`${formatDate(b.bookingDate)}, ${b.startTime}${b.endTime ? ` – ${b.endTime}` : ''}`}
              />
              <InfoRow
                icon={<MapPin className="h-4 w-4" />}
                label="Meeting location"
                value={b.meetingLocation || '—'}
              />
              <InfoRow
                icon={<ShieldCheck className="h-4 w-4" />}
                label="Place type"
                value={b.meetingPlaceType || '—'}
              />
              <InfoRow
                icon={<Clock className="h-4 w-4" />}
                label="Duration"
                value={`${b.durationHours} hour${b.durationHours === 1 ? '' : 's'}`}
              />
              {b.category?.name && (
                <InfoRow
                  icon={<CalendarClock className="h-4 w-4" />}
                  label="Category"
                  value={b.category.name}
                />
              )}
            </div>

            {b.notes && (
              <div className="mt-5 rounded-md border-2 border-ink bg-white p-3">
                <p className="text-xs font-bold uppercase tracking-wide text-slate-500">Notes</p>
                <p className="mt-1 text-sm text-slate-700">{b.notes}</p>
              </div>
            )}

            {b.cancellationReason && (
              <div className="mt-5 rounded-md border-2 border-ink bg-rose-50/70 p-3">
                <p className="text-xs font-bold uppercase tracking-wide text-rose-600">
                  Cancellation reason
                </p>
                <p className="mt-1 text-sm text-rose-700">{b.cancellationReason}</p>
              </div>
            )}
          </Card>

          {/* Money breakdown */}
          <Card>
            <CardHeader title="Payment breakdown" />
            <dl className="space-y-3 text-sm">
              {b.hourlyRate != null && (
                <KeyVal
                  k={`Hourly rate × ${b.durationHours}h`}
                  v={formatINR(b.hourlyRate)}
                />
              )}
              <KeyVal k="Total amount" v={<strong>{formatINR(total)}</strong>} />
              <KeyVal
                k={`Platform commission${b.commissionRate != null ? ` (${b.commissionRate}%)` : ''}`}
                v={commission != null ? `− ${formatINR(commission)}` : '—'}
              />
              <div className="border-t-2 border-ink pt-3">
                <KeyVal
                  k="Companion payout"
                  v={
                    <span className="font-semibold text-emerald-700">
                      {payout != null ? formatINR(payout) : '—'}
                    </span>
                  }
                />
              </div>
            </dl>
          </Card>

          {/* Linked payment */}
          <Card>
            <CardHeader
              title="Payment"
              subtitle="Razorpay transaction"
              action={b.payment ? <StatusBadge status={b.payment.status} /> : undefined}
            />
            {b.payment ? (
              <dl className="space-y-3 text-sm">
                <KeyVal k="Amount" v={formatINR(b.payment.amount)} />
                <KeyVal k="Method" v={b.payment.method ?? 'razorpay'} />
                <KeyVal
                  k="Razorpay order"
                  v={<Mono value={b.payment.razorpayOrderId} />}
                />
                <KeyVal
                  k="Razorpay payment"
                  v={<Mono value={b.payment.razorpayPaymentId} />}
                />
                <KeyVal
                  k="Captured at"
                  v={b.payment.capturedAt ? formatDateTime(b.payment.capturedAt) : '—'}
                />
              </dl>
            ) : (
              <div className="flex items-center gap-2 text-sm text-slate-400">
                <Receipt className="h-4 w-4" />
                No payment recorded for this booking yet.
              </div>
            )}
          </Card>
        </div>

        {/* Right: parties + timeline */}
        <div className="space-y-6">
          <Card>
            <CardHeader title="Customer" />
            <PartyBlock
              name={customerName}
              mobile={b.customer?.mobileNumber}
              email={b.customer?.email}
              href={b.customer?.id ? `/users/${b.customer.id}` : undefined}
              linkLabel="View customer →"
            />
          </Card>

          <Card>
            <CardHeader title="Companion" />
            <PartyBlock
              name={companionName}
              mobile={b.companion?.user?.mobileNumber}
              email={b.companion?.user?.email}
              href={b.companionId ? `/companions/${b.companionId}` : undefined}
              linkLabel="View companion →"
            />
          </Card>

          {/* Meet-at-location start verification */}
          {(b.startCode || b.startedAt) && (
            <Card>
              <CardHeader
                title="Start verification"
                subtitle="Meet-at-location code"
              />
              {b.startCode && b.status === 'CONFIRMED' && (
                <div className="mb-3 rounded-md border-2 border-ink bg-acid p-3">
                  <p className="flex items-center gap-1.5 text-xs font-bold uppercase tracking-wide text-ink">
                    <KeyRound className="h-3.5 w-3.5" /> Customer start code
                  </p>
                  <p className="mt-1 font-mono text-2xl font-black tracking-[0.3em] text-ink">
                    {b.startCode}
                  </p>
                  <p className="mt-1 text-xs text-slate-700">
                    The customer reveals this to the companion in person to begin
                    the booking.
                  </p>
                </div>
              )}
              <dl className="space-y-3 text-sm">
                <KeyVal
                  k="Started at"
                  v={b.startedAt ? formatDateTime(b.startedAt) : 'Not started yet'}
                />
              </dl>
            </Card>
          )}

          {/* Status timeline */}
          <Card>
            <CardHeader title="Status timeline" />
            {history.length > 0 ? (
              <ol className="relative space-y-4 border-l-2 border-ink pl-4">
                {history.map((entry) => (
                  <li key={entry.id} className="relative">
                    <span className="absolute -left-[22px] top-1 h-2.5 w-2.5 rounded-full border-2 border-ink bg-brand-500" />
                    <div className="flex items-center gap-2">
                      <StatusBadge status={entry.status} />
                    </div>
                    <p className="mt-1 text-xs text-slate-400">
                      {formatDateTime(entry.createdAt)}
                    </p>
                    {entry.note && <p className="mt-1 text-sm text-slate-600">{entry.note}</p>}
                  </li>
                ))}
              </ol>
            ) : (
              <div className="space-y-2 text-sm">
                <div className="flex items-center justify-between">
                  <StatusBadge status={b.status} />
                </div>
                <p className="text-xs text-slate-400">
                  Created {formatDateTime(b.createdAt)}
                </p>
                {b.completedAt && (
                  <p className="text-xs text-slate-400">Completed {formatDateTime(b.completedAt)}</p>
                )}
              </div>
            )}
          </Card>
        </div>
      </div>

      {/* Cancel / refund modal */}
      <Modal
        open={action !== null}
        onClose={() => (busy ? null : setAction(null))}
        dismissible={!busy}
        title={
          action === 'cancel'
            ? 'Cancel booking'
            : action === 'start'
              ? 'Start booking'
              : 'Refund booking'
        }
        description={
          action === 'cancel'
            ? `Cancel ${b.bookingCode}. If it was paid, the refund policy is applied automatically.`
            : action === 'start'
              ? `Force-start ${b.bookingCode} without the customer's start code. Use this only when both parties have met and the code can't be entered.`
              : `Refund the payment for ${b.bookingCode} back to the customer.`
        }
        footer={
          <>
            <Button variant="ghost" onClick={() => setAction(null)} disabled={busy}>
              Close
            </Button>
            <Button
              variant={action === 'start' ? 'primary' : 'danger'}
              loading={busy}
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
            <label className="mb-1.5 block text-sm font-bold text-slate-700">Reason</label>
            <textarea
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              rows={3}
              autoFocus
              placeholder="e.g. Customer requested cancellation; companion unavailable."
              className="w-full rounded-md border-2 border-ink bg-white p-3 text-sm text-slate-900 transition-all focus:ring-2 focus:ring-brand-500/50"
            />
          </>
        ) : action === 'start' ? (
          <div className="space-y-2 text-sm text-slate-600">
            <p>
              This moves the booking to <strong>In progress</strong> and records the
              start time now. Normally the companion enters the customer&apos;s
              6-digit code instead.
            </p>
            {b.startCode && (
              <p className="rounded-md border-2 border-ink bg-white p-2.5">
                Customer start code:{' '}
                <span className="font-mono text-base font-bold tracking-widest text-brand-700">
                  {b.startCode}
                </span>
              </p>
            )}
          </div>
        ) : (
          <Input
            label="Refund amount (₹)"
            type="number"
            min={1}
            step="0.01"
            value={refundAmount}
            onChange={(e) => setRefundAmount(e.target.value)}
            hint={`Leave blank for a full refund of ${formatINR(total)}.`}
            placeholder={String(total)}
          />
        )}
        {actionError && action !== null && (
          <p className="mt-2 text-xs text-rose-600">{actionError}</p>
        )}
      </Modal>
    </div>
  );
}

function round2(n: number): number {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

function BackLink() {
  return (
    <Link
      href="/bookings"
      className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-slate-500 transition-colors hover:text-brand-600"
    >
      <ArrowLeft className="h-4 w-4" />
      Back to bookings
    </Link>
  );
}

function PartyBlock({
  name,
  mobile,
  email,
  href,
  linkLabel,
}: {
  name: string;
  mobile?: string | null;
  email?: string | null;
  href?: string;
  linkLabel: string;
}) {
  const initial = (name || '?').charAt(0).toUpperCase();
  return (
    <div>
      <div className="flex items-center gap-3">
        <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full border-2 border-ink bg-brand-50 text-sm font-bold text-brand-700">
          {initial}
        </span>
        <div className="min-w-0">
          <p className="truncate font-medium text-slate-900">{name}</p>
          <p className="truncate text-xs text-slate-500">
            {mobile || '—'}
            {email ? ` · ${email}` : ''}
          </p>
        </div>
      </div>
      {href && (
        <Link
          href={href}
          className="mt-3 inline-flex items-center gap-1 text-sm font-medium text-brand-600 hover:text-brand-700"
        >
          <User className="h-3.5 w-3.5" />
          {linkLabel}
        </Link>
      )}
    </div>
  );
}

function InfoRow({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
}) {
  return (
    <div className="flex items-start gap-2.5">
      <span className="mt-0.5 text-slate-400">{icon}</span>
      <div className="min-w-0">
        <p className="text-xs text-slate-400">{label}</p>
        <p className="text-sm font-medium text-slate-800">{value}</p>
      </div>
    </div>
  );
}

function KeyVal({ k, v }: { k: string; v: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <dt className="text-slate-500">{k}</dt>
      <dd className="text-right font-medium text-slate-800">{v}</dd>
    </div>
  );
}

function Mono({ value }: { value?: string | null }) {
  if (!value) return <span className="text-slate-400">—</span>;
  return <span className="font-mono text-xs text-slate-700">{value}</span>;
}

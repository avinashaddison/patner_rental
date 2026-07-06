'use client';

/**
 * Admin → User detail
 *
 * Full account view: profile, wallet, KYC documents, recent bookings (as customer or
 * companion), and a safety summary (reports received, SOS alerts). Block / unblock
 * from here. If the user is a companion, links through to the companion moderation page.
 *
 * Backed by:
 *   GET  /admin/users/:id          (detail incl. wallet, kycDocuments, recentBookings, counts)
 *   POST /admin/users/:id/block    { reason }
 *   POST /admin/users/:id/unblock
 */

import { useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import useSWR from 'swr';
import {
  AlertTriangle,
  ArrowLeft,
  Ban,
  CalendarClock,
  CheckCircle2,
  Flag,
  HeartHandshake,
  Mail,
  MapPin,
  Phone,
  ShieldOff,
  Wallet,
} from 'lucide-react';
import { PageHeader } from '@/components/ui/PageHeader';
import { Card, CardHeader } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { Badge, StatusBadge } from '@/components/ui/Badge';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { LoadingState } from '@/components/ui/Spinner';
import { swrFetcher, apiFetch, ApiError } from '@/lib/api';
import { formatINR, formatDate, formatDateTime } from '@/lib/format';
import type { AdminUser, AdminBooking } from '@/lib/types';

export default function UserDetailPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const id = params?.id;

  const { data, isLoading, error, mutate } = useSWR<AdminUser>(
    id ? `/users/${id}` : null,
    swrFetcher,
    { revalidateOnFocus: false },
  );

  const [busy, setBusy] = useState(false);
  const [blockOpen, setBlockOpen] = useState(false);
  const [reason, setReason] = useState('');
  const [actionError, setActionError] = useState<string | null>(null);

  async function runUnblock() {
    if (!id) return;
    setBusy(true);
    setActionError(null);
    try {
      await apiFetch(`/users/${id}/unblock`, { method: 'POST' });
      await mutate();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Failed to unblock user.');
    } finally {
      setBusy(false);
    }
  }

  async function confirmBlock() {
    if (!id) return;
    const trimmed = reason.trim();
    if (!trimmed) {
      setActionError('A reason is required.');
      return;
    }
    setBusy(true);
    setActionError(null);
    try {
      await apiFetch(`/users/${id}/block`, { method: 'POST', body: { reason: trimmed } });
      setBlockOpen(false);
      setReason('');
      await mutate();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Failed to block user.');
    } finally {
      setBusy(false);
    }
  }

  if (isLoading) return <LoadingState label="Loading user…" />;

  if (error || !data) {
    return (
      <div>
        <BackLink />
        <Card className="border-2 border-ink bg-rose-50/60">
          <p className="text-sm text-rose-700">
            Couldn’t load this user. {(error as Error)?.message ?? 'Not found.'}
          </p>
        </Card>
      </div>
    );
  }

  const u = data;
  const isAdmin = u.role === 'ADMIN';
  const reportsReceived = u.counts?.reportsReceived ?? 0;
  const sosAlerts = u.counts?.sosAlerts ?? 0;
  const bookings = u.recentBookings ?? [];

  const bookingColumns: Column<AdminBooking>[] = [
    {
      key: 'code',
      header: 'Code',
      render: (b) => <span className="font-medium text-slate-800">{b.bookingCode}</span>,
    },
    {
      key: 'activity',
      header: 'Activity',
      render: (b) => (
        <div className="min-w-0">
          <p className="truncate text-slate-800">{b.activity}</p>
          <p className="truncate text-xs text-slate-400">{b.meetingPlaceType}</p>
        </div>
      ),
    },
    {
      key: 'date',
      header: 'Date',
      hideOnMobile: true,
      accessor: (b) => <span className="text-slate-600">{formatDate(b.bookingDate)}</span>,
    },
    {
      key: 'amount',
      header: 'Amount',
      align: 'right',
      render: (b) => <span className="font-medium text-slate-800">{formatINR(b.totalAmount)}</span>,
    },
    {
      key: 'status',
      header: 'Status',
      align: 'center',
      render: (b) => <StatusBadge status={b.status} />,
    },
  ];

  return (
    <div>
      <BackLink />

      <PageHeader
        eyebrow="User"
        title={u.fullName}
        description={`${u.role.charAt(0) + u.role.slice(1).toLowerCase()} · joined ${formatDate(u.createdAt)}`}
        actions={
          isAdmin ? (
            <Badge tone="gray">Admin account</Badge>
          ) : u.isBlocked ? (
            <Button
              variant="success"
              loading={busy}
              onClick={runUnblock}
              leftIcon={<CheckCircle2 className="h-4 w-4" />}
            >
              Unblock
            </Button>
          ) : (
            <Button
              variant="danger"
              onClick={() => {
                setBlockOpen(true);
                setReason('');
                setActionError(null);
              }}
              leftIcon={<Ban className="h-4 w-4" />}
            >
              Block user
            </Button>
          )
        }
      />

      {/* Status strip */}
      <div className="mb-6 flex flex-wrap items-center gap-2">
        {u.isBlocked ? (
          <Badge tone="red" dot>
            Blocked
          </Badge>
        ) : (
          <Badge tone="green" dot>
            Active
          </Badge>
        )}
        <Badge tone={u.role === 'COMPANION' ? 'brand' : u.role === 'CUSTOMER' ? 'blue' : 'gray'}>
          {u.role.charAt(0) + u.role.slice(1).toLowerCase()}
        </Badge>
        {u.isMobileVerified && <Badge tone="green">Mobile verified</Badge>}
        {reportsReceived > 0 && (
          <Badge tone="amber">
            <Flag className="h-3 w-3" /> {reportsReceived} report{reportsReceived > 1 ? 's' : ''}
          </Badge>
        )}
      </div>

      {u.isBlocked && u.blockedReason && (
        <Card className="mb-6 border-2 border-ink bg-rose-50/70">
          <div className="flex items-start gap-2.5">
            <ShieldOff className="mt-0.5 h-4 w-4 shrink-0 text-rose-500" />
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-rose-600">
                Account blocked
              </p>
              <p className="mt-0.5 text-sm text-rose-700">{u.blockedReason}</p>
            </div>
          </div>
        </Card>
      )}

      {actionError && !blockOpen && (
        <Card className="mb-4 border-2 border-ink bg-rose-50/70">
          <p className="text-sm text-rose-700">{actionError}</p>
        </Card>
      )}

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        {/* Left column: bookings + KYC */}
        <div className="space-y-6 lg:col-span-2">
          <Card flush>
            <div className="px-5 pt-5">
              <CardHeader
                title="Recent bookings"
                subtitle={`${bookings.length} most recent`}
              />
            </div>
            <DataTable
              columns={bookingColumns}
              rows={bookings}
              rowKey={(b) => b.id}
              emptyIcon={<CalendarClock className="h-8 w-8" />}
              emptyMessage="No bookings for this user yet."
              onRowClick={(b) => router.push(`/bookings/${b.id}`)}
              className="rounded-none border-0 shadow-none"
            />
          </Card>

          {u.kycDocuments && u.kycDocuments.length > 0 && (
            <Card>
              <CardHeader title="KYC documents" />
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                {u.kycDocuments.map((doc) => (
                  <div key={doc.id} className="overflow-hidden rounded-md border-2 border-ink bg-white shadow-brutal-xs">
                    <a
                      href={doc.documentUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="block aspect-video overflow-hidden border-b-2 border-ink bg-slate-50"
                    >
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img
                        src={doc.documentUrl}
                        alt={doc.docType}
                        className="h-full w-full object-cover transition-transform hover:scale-105"
                      />
                    </a>
                    <div className="flex items-center justify-between px-3 py-2.5">
                      <span className="text-sm font-medium text-slate-800">
                        {doc.docType === 'GOVERNMENT_ID' ? 'Government ID' : 'Selfie'}
                      </span>
                      <StatusBadge status={doc.status} />
                    </div>
                  </div>
                ))}
              </div>
            </Card>
          )}
        </div>

        {/* Right column: profile, safety, wallet, companion link */}
        <div className="space-y-6">
          <Card>
            <CardHeader title="Profile" />
            <dl className="space-y-3 text-sm">
              <IconRow icon={<Phone className="h-4 w-4" />} label="Mobile" value={u.mobileNumber} />
              <IconRow icon={<Mail className="h-4 w-4" />} label="Email" value={u.email || '—'} />
              {u.username && (
                <KeyVal k="Username" v={<code className="text-slate-700">@{u.username}</code>} />
              )}
              <IconRow icon={<MapPin className="h-4 w-4" />} label="City" value={u.city || '—'} />
              <IconRow
                icon={<CalendarClock className="h-4 w-4" />}
                label="Date of birth"
                value={u.dateOfBirth ? `${formatDate(u.dateOfBirth)}${u.age ? ` (${u.age}y)` : ''}` : '—'}
              />
              {u.referralCode && (
                <KeyVal k="Referral code" v={<code className="text-slate-700">{u.referralCode}</code>} />
              )}
              <KeyVal k="Last active" v={u.lastActiveAt ? formatDateTime(u.lastActiveAt) : '—'} />
            </dl>
          </Card>

          {/* Safety summary */}
          <Card>
            <CardHeader title="Safety" />
            <div className="grid grid-cols-2 gap-3">
              <SafetyTile
                icon={<Flag className="h-4 w-4" />}
                label="Reports received"
                value={reportsReceived}
                alert={reportsReceived > 0}
              />
              <SafetyTile
                icon={<AlertTriangle className="h-4 w-4" />}
                label="SOS alerts"
                value={sosAlerts}
                alert={sosAlerts > 0}
              />
            </div>
            {reportsReceived > 0 && (
              <Link
                href={`/complaints?q=${encodeURIComponent(u.fullName)}`}
                className="mt-3 inline-block text-sm font-medium text-brand-600 hover:text-brand-700"
              >
                Review complaints →
              </Link>
            )}
          </Card>

          {u.wallet && (
            <Card>
              <CardHeader
                title="Wallet"
                action={<Wallet className="h-4 w-4 text-slate-400" />}
              />
              <dl className="space-y-3 text-sm">
                <KeyVal k="Balance" v={formatINR(u.wallet.balance)} />
                <KeyVal k="Pending" v={formatINR(u.wallet.pendingBalance)} />
                <KeyVal k="Total earned" v={formatINR(u.wallet.totalEarned)} />
                <KeyVal k="Withdrawn" v={formatINR(u.wallet.totalWithdrawn)} />
              </dl>
            </Card>
          )}

          {u.companion && (
            <Card className="border-2 border-ink bg-acid">
              <div className="flex items-center gap-3">
                <span className="flex h-10 w-10 items-center justify-center rounded-md border-2 border-ink bg-brand-500 text-white shadow-brutal-xs">
                  <HeartHandshake className="h-5 w-5" />
                </span>
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-semibold text-slate-900">Companion profile</p>
                  <p className="text-xs text-slate-500">
                    Status <StatusBadge status={u.companion.status} />
                  </p>
                </div>
              </div>
              <Link href={`/companions/${u.companion.id}`}>
                <Button variant="secondary" size="sm" className="mt-3 w-full">
                  Open companion moderation
                </Button>
              </Link>
            </Card>
          )}
        </div>
      </div>

      {/* Block modal */}
      <Modal
        open={blockOpen}
        onClose={() => (busy ? null : setBlockOpen(false))}
        dismissible={!busy}
        title="Block user"
        description={`${u.fullName} will lose access. If they are a companion, their listing is suspended too.`}
        footer={
          <>
            <Button variant="ghost" onClick={() => setBlockOpen(false)} disabled={busy}>
              Cancel
            </Button>
            <Button variant="danger" loading={busy} onClick={confirmBlock}>
              Block user
            </Button>
          </>
        }
      >
        <label className="mb-1.5 block text-sm font-medium text-slate-700">Reason</label>
        <textarea
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          rows={3}
          autoFocus
          placeholder="e.g. Repeated harassment reports confirmed."
          className="w-full rounded-md border-2 border-ink bg-white p-3 text-sm text-slate-900 transition-colors focus:border-brand-500 focus:ring-2 focus:ring-brand-500/50"
        />
        {actionError && blockOpen && <p className="mt-2 text-xs text-rose-600">{actionError}</p>}
      </Modal>
    </div>
  );
}

function BackLink() {
  return (
    <Link
      href="/users"
      className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-slate-500 transition-colors hover:text-brand-600"
    >
      <ArrowLeft className="h-4 w-4" />
      Back to users
    </Link>
  );
}

function IconRow({
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
      <div className="min-w-0 flex-1">
        <p className="text-xs text-slate-400">{label}</p>
        <p className="truncate font-medium text-slate-800">{value}</p>
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

function SafetyTile({
  icon,
  label,
  value,
  alert,
}: {
  icon: React.ReactNode;
  label: string;
  value: number;
  alert: boolean;
}) {
  return (
    <div
      className={
        'rounded-md border-2 border-ink p-3 ' +
        (alert ? 'bg-amber-50/70 shadow-brutal-xs' : 'bg-white')
      }
    >
      <span className={alert ? 'text-amber-600' : 'text-slate-400'}>{icon}</span>
      <p className="mt-1.5 text-xl font-bold text-slate-900">{value}</p>
      <p className="text-xs text-slate-500">{label}</p>
    </div>
  );
}

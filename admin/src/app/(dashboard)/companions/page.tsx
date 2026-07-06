'use client';

/**
 * Admin → Companions
 *
 * Moderation queue for companion profiles. Tabs by `CompanionStatus`
 * (PENDING / APPROVED / REJECTED / SUSPENDED). For each companion an admin can
 * approve, reject, suspend, or toggle "featured".
 *
 * Backed by:
 *   GET  /admin/companions?status=&q=&page=&limit=
 *   POST /admin/companions/:id/approve
 *   POST /admin/companions/:id/reject   { reason }
 *   POST /admin/companions/:id/suspend  { reason }
 *   POST /admin/companions/:id/feature  { isFeatured }
 *
 * (Routes/fields match docs/API.md → ADMIN API.)
 */

import { useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import useSWR from 'swr';
import {
  BadgeCheck,
  Ban,
  CheckCircle2,
  Search,
  Sparkles,
  Star,
  XCircle,
} from 'lucide-react';
import { PageHeader } from '@/components/ui/PageHeader';
import { Card } from '@/components/ui/Card';
import { Input } from '@/components/ui/Input';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { Badge, StatusBadge } from '@/components/ui/Badge';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { apiFetch, apiFetchList, ApiError } from '@/lib/api';
import { formatINR, formatDate } from '@/lib/format';
import type { AdminCompanion } from '@/lib/types';

const TABS = ['PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED'] as const;
type Tab = (typeof TABS)[number];

const TAB_LABEL: Record<Tab, string> = {
  PENDING: 'Pending',
  APPROVED: 'Approved',
  REJECTED: 'Rejected',
  SUSPENDED: 'Suspended',
};

const PAGE_SIZE = 20;

interface CompanionListResponse {
  data: AdminCompanion[];
  meta?: { total: number };
}

type PendingAction =
  | { kind: 'reject'; companion: AdminCompanion }
  | { kind: 'suspend'; companion: AdminCompanion };

export default function CompanionsPage() {
  const router = useRouter();
  const [tab, setTab] = useState<Tab>('PENDING');
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(1);

  // Per-row inline action loading (approve / feature).
  const [busyId, setBusyId] = useState<string | null>(null);
  // Reason-required actions go through a modal.
  const [pending, setPending] = useState<PendingAction | null>(null);
  const [reason, setReason] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const swrKey = useMemo(
    () =>
      `/companions?status=${tab}&page=${page}&limit=${PAGE_SIZE}` +
      (query ? `&q=${encodeURIComponent(query)}` : ''),
    [tab, page, query],
  );

  const { data, isLoading, error, mutate } = useSWR<CompanionListResponse>(
    swrKey,
    (path: string) =>
      apiFetchList<AdminCompanion[]>(path).then((r) => ({ data: r.data ?? [], meta: r.meta })),
    { revalidateOnFocus: false, keepPreviousData: true },
  );

  const rows = data?.data ?? [];
  const total = data?.meta?.total ?? rows.length;

  function switchTab(next: Tab) {
    setTab(next);
    setPage(1);
  }

  function submitSearch(e: React.FormEvent) {
    e.preventDefault();
    setPage(1);
    setQuery(search.trim());
  }

  async function runApprove(c: AdminCompanion) {
    setBusyId(c.id);
    setActionError(null);
    try {
      await apiFetch(`/companions/${c.id}/approve`, { method: 'POST' });
      await mutate();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Failed to approve companion.');
    } finally {
      setBusyId(null);
    }
  }

  async function runFeature(c: AdminCompanion, isFeatured: boolean) {
    setBusyId(c.id);
    setActionError(null);
    try {
      await apiFetch(`/companions/${c.id}/feature`, {
        method: 'POST',
        body: { isFeatured },
      });
      await mutate();
    } catch (err) {
      setActionError(
        err instanceof ApiError ? err.message : 'Failed to update featured status.',
      );
    } finally {
      setBusyId(null);
    }
  }

  function openReasonModal(action: PendingAction) {
    setPending(action);
    setReason('');
    setActionError(null);
  }

  async function confirmReasonAction() {
    if (!pending) return;
    const trimmed = reason.trim();
    if (!trimmed) {
      setActionError('A reason is required.');
      return;
    }
    setSubmitting(true);
    setActionError(null);
    try {
      const path =
        pending.kind === 'reject'
          ? `/companions/${pending.companion.id}/reject`
          : `/companions/${pending.companion.id}/suspend`;
      await apiFetch(path, { method: 'POST', body: { reason: trimmed } });
      setPending(null);
      await mutate();
    } catch (err) {
      setActionError(
        err instanceof ApiError ? err.message : 'Action failed. Please try again.',
      );
    } finally {
      setSubmitting(false);
    }
  }

  const columns: Column<AdminCompanion>[] = [
    {
      key: 'companion',
      header: 'Companion',
      render: (c) => <CompanionCell companion={c} />,
    },
    {
      key: 'city',
      header: 'City',
      hideOnMobile: true,
      accessor: (c) => <span className="text-slate-600">{c.city || '—'}</span>,
    },
    {
      key: 'rate',
      header: 'Rate / hr',
      align: 'right',
      render: (c) => (
        <span className="font-medium text-slate-800">{formatINR(c.hourlyRate)}</span>
      ),
    },
    {
      key: 'rating',
      header: 'Rating',
      align: 'center',
      hideOnMobile: true,
      render: (c) => (
        <span className="inline-flex items-center gap-1 text-slate-700">
          <Star className="h-3.5 w-3.5 fill-amber-400 text-amber-400" />
          {(c.ratingAvg ?? 0).toFixed(1)}
          <span className="text-xs text-slate-400">({c.ratingCount ?? 0})</span>
        </span>
      ),
    },
    {
      key: 'bookings',
      header: 'Bookings',
      align: 'center',
      hideOnMobile: true,
      accessor: (c) => c.totalBookings ?? 0,
    },
    {
      key: 'status',
      header: 'Status',
      align: 'center',
      render: (c) => (
        <div className="flex flex-col items-center gap-1">
          <StatusBadge status={c.status} />
          {c.isFeatured && (
            <Badge tone="brand" className="text-[10px]">
              <Sparkles className="h-3 w-3" /> Featured
            </Badge>
          )}
        </div>
      ),
    },
    {
      key: 'joined',
      header: 'Joined',
      hideOnMobile: true,
      accessor: (c) => <span className="text-slate-500">{formatDate(c.createdAt)}</span>,
    },
    {
      key: 'actions',
      header: 'Actions',
      align: 'right',
      render: (c) => (
        <RowActions
          companion={c}
          busy={busyId === c.id}
          onApprove={() => runApprove(c)}
          onReject={() => openReasonModal({ kind: 'reject', companion: c })}
          onSuspend={() => openReasonModal({ kind: 'suspend', companion: c })}
          onFeature={(v) => runFeature(c, v)}
        />
      ),
    },
  ];

  return (
    <div>
      <PageHeader
        eyebrow="Moderation"
        title="Companions"
        description="Review, approve and moderate companion profiles for the companionship marketplace."
        actions={
          <form onSubmit={submitSearch} className="flex items-center gap-2">
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search name, mobile, city…"
              leftIcon={<Search className="h-4 w-4" />}
              containerClassName="w-64"
              aria-label="Search companions"
            />
            <Button type="submit" variant="outline" size="md">
              Search
            </Button>
          </form>
        }
      />

      {/* Status tabs */}
      <div className="mb-4 flex flex-wrap gap-1 rounded-md border-2 border-ink bg-white p-1 shadow-brutal">
        {TABS.map((t) => {
          const active = t === tab;
          return (
            <button
              key={t}
              type="button"
              onClick={() => switchTab(t)}
              className={
                'rounded-md px-4 py-2 text-sm font-bold transition-all active:translate-x-0.5 active:translate-y-0.5 active:shadow-none ' +
                (active
                  ? 'border-2 border-ink bg-brand-500 text-white shadow-brutal-xs'
                  : 'border-2 border-transparent text-slate-600 hover:bg-acid')
              }
            >
              {TAB_LABEL[t]}
            </button>
          );
        })}
      </div>

      {actionError && !pending && (
        <Card className="mb-4 border-2 border-ink bg-rose-50/70">
          <p className="text-sm text-rose-700">{actionError}</p>
        </Card>
      )}

      {error ? (
        <Card className="border-2 border-ink bg-rose-50/60">
          <p className="text-sm text-rose-700">
            Couldn’t load companions. {(error as Error)?.message}
          </p>
        </Card>
      ) : (
        <DataTable
          columns={columns}
          rows={rows}
          rowKey={(c) => c.id}
          loading={isLoading}
          emptyMessage={`No ${TAB_LABEL[tab].toLowerCase()} companions.`}
          onRowClick={(c) => router.push(`/companions/${c.id}`)}
          pagination={{
            page,
            limit: PAGE_SIZE,
            total,
            onPageChange: setPage,
          }}
        />
      )}

      {/* Reason modal (reject / suspend) */}
      <Modal
        open={Boolean(pending)}
        onClose={() => (submitting ? null : setPending(null))}
        dismissible={!submitting}
        title={pending?.kind === 'reject' ? 'Reject companion' : 'Suspend companion'}
        description={
          pending
            ? `${pending.companion.name ?? 'This companion'} will be notified. This reason is recorded.`
            : undefined
        }
        footer={
          <>
            <Button variant="ghost" onClick={() => setPending(null)} disabled={submitting}>
              Cancel
            </Button>
            <Button
              variant="danger"
              loading={submitting}
              onClick={confirmReasonAction}
            >
              {pending?.kind === 'reject' ? 'Reject' : 'Suspend'}
            </Button>
          </>
        }
      >
        <label className="mb-1.5 block text-sm font-bold text-ink">Reason</label>
        <textarea
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          rows={3}
          autoFocus
          placeholder={
            pending?.kind === 'reject'
              ? 'e.g. Profile photos do not meet guidelines.'
              : 'e.g. Multiple verified complaints.'
          }
          className="w-full rounded-md border-2 border-ink bg-white p-3 text-sm text-slate-900 transition-colors focus:border-brand-500 focus:ring-2 focus:ring-brand-500/50"
        />
        {actionError && pending && <p className="mt-2 text-xs text-rose-600">{actionError}</p>}
      </Modal>
    </div>
  );
}

function CompanionCell({ companion }: { companion: AdminCompanion }) {
  const name = companion.name ?? companion.user?.fullName ?? 'Unnamed';
  const photo = companion.photos?.find((p) => p.isPrimary)?.photoUrl ?? companion.photos?.[0]?.photoUrl;
  const initial = name.charAt(0).toUpperCase();
  return (
    <div className="flex items-center gap-3">
      {photo ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={photo}
          alt={name}
          className="h-10 w-10 shrink-0 rounded-full border-2 border-ink object-cover"
        />
      ) : (
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full border-2 border-ink bg-brand-50 text-sm font-bold text-brand-700">
          {initial}
        </span>
      )}
      <div className="min-w-0">
        <p className="flex items-center gap-1 truncate font-bold text-ink">
          {name}
          {companion.age ? <span className="text-xs text-slate-400">· {companion.age}y</span> : null}
        </p>
        <p className="truncate text-xs text-slate-500">
          {companion.user?.mobileNumber ?? '—'}
        </p>
      </div>
    </div>
  );
}

function RowActions({
  companion,
  busy,
  onApprove,
  onReject,
  onSuspend,
  onFeature,
}: {
  companion: AdminCompanion;
  busy: boolean;
  onApprove: () => void;
  onReject: () => void;
  onSuspend: () => void;
  onFeature: (isFeatured: boolean) => void;
}) {
  const stop = (fn: () => void) => (e: React.MouseEvent) => {
    e.stopPropagation();
    fn();
  };
  const { status } = companion;

  return (
    <div className="flex items-center justify-end gap-1.5">
      {status === 'PENDING' && (
        <Button
          size="sm"
          variant="success"
          loading={busy}
          onClick={stop(onApprove)}
          leftIcon={<CheckCircle2 className="h-3.5 w-3.5" />}
        >
          Approve
        </Button>
      )}

      {status === 'APPROVED' && (
        <>
          <Button
            size="sm"
            variant={companion.isFeatured ? 'secondary' : 'outline'}
            loading={busy}
            onClick={stop(() => onFeature(!companion.isFeatured))}
            leftIcon={<Sparkles className="h-3.5 w-3.5" />}
          >
            {companion.isFeatured ? 'Unfeature' : 'Feature'}
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={stop(onSuspend)}
            leftIcon={<Ban className="h-3.5 w-3.5" />}
          >
            Suspend
          </Button>
        </>
      )}

      {(status === 'REJECTED' || status === 'SUSPENDED') && (
        <Button
          size="sm"
          variant="success"
          loading={busy}
          onClick={stop(onApprove)}
          leftIcon={<BadgeCheck className="h-3.5 w-3.5" />}
        >
          Re-approve
        </Button>
      )}

      {status === 'PENDING' && (
        <Button
          size="sm"
          variant="outline"
          onClick={stop(onReject)}
          leftIcon={<XCircle className="h-3.5 w-3.5" />}
        >
          Reject
        </Button>
      )}
    </div>
  );
}

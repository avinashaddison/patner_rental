'use client';

/**
 * Admin → Payouts
 *
 * Companion withdrawal requests. Review the destination (UPI id or bank account),
 * then process (mark processing → completed) or reject a request. Filter by status
 * and search by companion. All amounts are in INR.
 *
 * Backed by:
 *   GET  /admin/payouts?status=&q=&page=&limit=
 *   POST /admin/payouts/:id/process   (mark processing/completed)
 *   POST /admin/payouts/:id/reject    { reason }
 */

import { useMemo, useState } from 'react';
import useSWR from 'swr';
import {
  Banknote,
  CheckCircle2,
  Landmark,
  Search,
  Smartphone,
  Wallet,
  XCircle,
} from 'lucide-react';
import { PageHeader } from '@/components/ui/PageHeader';
import { Card } from '@/components/ui/Card';
import { StatCard } from '@/components/ui/StatCard';
import { Input } from '@/components/ui/Input';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { Select } from '@/components/ui/Select';
import { Badge, StatusBadge } from '@/components/ui/Badge';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { apiFetch, apiFetchList, ApiError } from '@/lib/api';
import { formatINR, formatDateTime } from '@/lib/format';
import type { AdminPayout } from '@/lib/types';

const PAGE_SIZE = 20;

const STATUS_OPTIONS = [
  { label: 'All statuses', value: '' },
  { label: 'Requested', value: 'REQUESTED' },
  { label: 'Processing', value: 'PROCESSING' },
  { label: 'Completed', value: 'COMPLETED' },
  { label: 'Failed', value: 'FAILED' },
  { label: 'Rejected', value: 'REJECTED' },
];

/** Statuses an admin can still act on. */
const ACTIONABLE = new Set(['REQUESTED', 'PROCESSING']);

interface PayoutMeta {
  total?: number;
  totalRequested?: number;
  pendingAmount?: number;
}

interface PayoutListResponse {
  data: AdminPayout[];
  meta?: PayoutMeta;
}

export default function PayoutsPage() {
  const [status, setStatus] = useState('REQUESTED');
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(1);

  const [busyId, setBusyId] = useState<string | null>(null);
  const [rejectTarget, setRejectTarget] = useState<AdminPayout | null>(null);
  const [reason, setReason] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [banner, setBanner] = useState<string | null>(null);

  const swrKey = useMemo(() => {
    const p = new URLSearchParams();
    p.set('page', String(page));
    p.set('limit', String(PAGE_SIZE));
    if (status) p.set('status', status);
    if (query) p.set('q', query);
    return `/payouts?${p.toString()}`;
  }, [status, query, page]);

  const { data, isLoading, error, mutate } = useSWR<PayoutListResponse>(
    swrKey,
    (path: string) =>
      apiFetchList<AdminPayout[]>(path).then((r) => ({
        data: r.data ?? [],
        meta: r.meta as PayoutMeta | undefined,
      })),
    { revalidateOnFocus: false, keepPreviousData: true },
  );

  const rows = data?.data ?? [];
  const meta = data?.meta;
  const total = meta?.total ?? rows.length;

  const pendingAmount =
    meta?.pendingAmount ??
    rows
      .filter((p) => ACTIONABLE.has(p.status))
      .reduce((s, p) => s + (p.amount || 0), 0);
  const derived = meta?.pendingAmount === undefined;

  function submitSearch(e: React.FormEvent) {
    e.preventDefault();
    setPage(1);
    setQuery(search.trim());
  }

  async function runProcess(payout: AdminPayout) {
    setBusyId(payout.id);
    setActionError(null);
    try {
      await apiFetch(`/payouts/${payout.id}/process`, { method: 'POST' });
      setBanner(
        `Payout of ${formatINR(payout.amount)} to ${
          payout.user?.fullName ?? 'companion'
        } advanced.`,
      );
      await mutate();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Failed to process payout.');
    } finally {
      setBusyId(null);
    }
  }

  function openReject(payout: AdminPayout) {
    setRejectTarget(payout);
    setReason('');
    setActionError(null);
  }

  async function confirmReject() {
    if (!rejectTarget) return;
    const trimmed = reason.trim();
    if (!trimmed) {
      setActionError('A reason is required.');
      return;
    }
    setSubmitting(true);
    setActionError(null);
    try {
      await apiFetch(`/payouts/${rejectTarget.id}/reject`, {
        method: 'POST',
        body: { reason: trimmed },
      });
      setBanner(`Payout request from ${rejectTarget.user?.fullName ?? 'companion'} rejected.`);
      setRejectTarget(null);
      await mutate();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Failed to reject payout.');
    } finally {
      setSubmitting(false);
    }
  }

  const columns: Column<AdminPayout>[] = [
    {
      key: 'companion',
      header: 'Companion',
      render: (p) => (
        <div className="min-w-0">
          <p className="truncate font-medium text-slate-900">
            {p.user?.fullName ?? 'Unknown companion'}
          </p>
          <p className="truncate text-xs text-slate-500">{p.user?.mobileNumber ?? '—'}</p>
        </div>
      ),
    },
    {
      key: 'destination',
      header: 'Destination',
      hideOnMobile: true,
      render: (p) => <DestinationCell payout={p} />,
    },
    {
      key: 'requested',
      header: 'Requested',
      hideOnMobile: true,
      render: (p) => <span className="text-slate-500">{formatDateTime(p.createdAt)}</span>,
    },
    {
      key: 'amount',
      header: 'Amount',
      align: 'right',
      render: (p) => <span className="font-medium text-slate-900">{formatINR(p.amount)}</span>,
    },
    {
      key: 'status',
      header: 'Status',
      align: 'center',
      render: (p) => <StatusBadge status={p.status} />,
    },
    {
      key: 'actions',
      header: 'Actions',
      align: 'right',
      render: (p) => {
        if (!ACTIONABLE.has(p.status)) {
          return <span className="text-xs text-slate-400">—</span>;
        }
        return (
          <div className="flex items-center justify-end gap-2">
            <Button
              size="sm"
              variant="success"
              loading={busyId === p.id}
              onClick={() => runProcess(p)}
              leftIcon={<CheckCircle2 className="h-3.5 w-3.5" />}
            >
              {p.status === 'REQUESTED' ? 'Process' : 'Complete'}
            </Button>
            <Button
              size="sm"
              variant="outline"
              disabled={busyId === p.id}
              onClick={() => openReject(p)}
              leftIcon={<XCircle className="h-3.5 w-3.5" />}
            >
              Reject
            </Button>
          </div>
        );
      },
    },
  ];

  return (
    <div>
      <PageHeader
        eyebrow="Finance"
        title="Payouts"
        description="Review and settle companion withdrawal requests to UPI or bank accounts."
      />

      {/* Totals */}
      <div className="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <StatCard
          label="Pending payouts"
          value={formatINR(pendingAmount)}
          tone="amber"
          icon={<Wallet className="h-5 w-5" />}
          deltaLabel={derived ? 'this page' : 'awaiting settlement'}
        />
        <StatCard
          label="Open requests"
          value={String(
            meta?.totalRequested ??
              rows.filter((p) => ACTIONABLE.has(p.status)).length,
          )}
          tone="brand"
          icon={<Banknote className="h-5 w-5" />}
          deltaLabel={derived ? 'this page' : 'queue'}
        />
      </div>

      {/* Filters */}
      <Card className="mb-4">
        <form onSubmit={submitSearch} className="flex flex-col gap-3 sm:flex-row sm:items-end">
          <Input
            label="Search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Companion name or mobile…"
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
        <Card className="mb-4 border-2 border-ink bg-lime-400">
          <div className="flex items-center justify-between gap-3">
            <p className="text-sm font-bold text-ink">{banner}</p>
            <button
              type="button"
              onClick={() => setBanner(null)}
              className="rounded-md border-2 border-ink bg-white px-2 py-1 text-xs font-bold text-ink shadow-brutal-xs transition-all hover:bg-acid active:translate-x-0.5 active:translate-y-0.5 active:shadow-none"
            >
              Dismiss
            </button>
          </div>
        </Card>
      )}

      {actionError && !rejectTarget && (
        <Card className="mb-4 border-2 border-ink bg-rose-50">
          <p className="text-sm font-bold text-rose-700">{actionError}</p>
        </Card>
      )}

      {error ? (
        <Card className="border-2 border-ink bg-rose-50">
          <p className="text-sm font-bold text-rose-700">
            Couldn’t load payouts. {(error as Error)?.message}
          </p>
        </Card>
      ) : (
        <DataTable
          columns={columns}
          rows={rows}
          rowKey={(p) => p.id}
          loading={isLoading}
          emptyMessage="No payout requests match these filters."
          emptyIcon={<Wallet className="h-8 w-8" />}
          pagination={{ page, limit: PAGE_SIZE, total, onPageChange: setPage }}
        />
      )}

      {/* Reject modal */}
      <Modal
        open={Boolean(rejectTarget)}
        onClose={() => (submitting ? null : setRejectTarget(null))}
        dismissible={!submitting}
        title="Reject payout request"
        description={
          rejectTarget
            ? `Reject the ${formatINR(rejectTarget.amount)} withdrawal from ${
                rejectTarget.user?.fullName ?? 'this companion'
              }. The amount stays in their wallet.`
            : undefined
        }
        footer={
          <>
            <Button variant="ghost" onClick={() => setRejectTarget(null)} disabled={submitting}>
              Cancel
            </Button>
            <Button variant="danger" loading={submitting} onClick={confirmReject}>
              Reject request
            </Button>
          </>
        }
      >
        <label className="mb-1.5 block text-sm font-bold text-slate-700">Reason</label>
        <textarea
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          rows={3}
          autoFocus
          placeholder="e.g. Bank details don’t match KYC; please re-submit."
          className="w-full rounded-md border-2 border-ink bg-white p-3 text-sm text-slate-900 transition-all focus:ring-2 focus:ring-brand-500/50"
        />
        {actionError && rejectTarget && <p className="mt-2 text-xs text-rose-600">{actionError}</p>}
      </Modal>
    </div>
  );
}

function DestinationCell({ payout }: { payout: AdminPayout }) {
  if (payout.method === 'UPI') {
    return (
      <div className="flex items-center gap-2">
        <Smartphone className="h-4 w-4 shrink-0 text-slate-400" />
        <div className="min-w-0">
          <Badge tone="blue">UPI</Badge>
          <p className="mt-1 truncate font-mono text-xs text-slate-700">
            {payout.upiId || '—'}
          </p>
        </div>
      </div>
    );
  }
  // BANK_TRANSFER
  const acct = payout.bankAccountNumber
    ? `••••${payout.bankAccountNumber.slice(-4)}`
    : '—';
  return (
    <div className="flex items-center gap-2">
      <Landmark className="h-4 w-4 shrink-0 text-slate-400" />
      <div className="min-w-0">
        <Badge tone="purple">Bank transfer</Badge>
        <p className="mt-1 truncate text-xs text-slate-700">
          {payout.bankAccountName || 'Account'} · {acct}
          {payout.ifsc ? ` · ${payout.ifsc}` : ''}
        </p>
      </div>
    </div>
  );
}

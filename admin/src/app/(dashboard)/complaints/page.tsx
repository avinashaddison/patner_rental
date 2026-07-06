'use client';

/**
 * Admin → Complaints
 *
 * Moderation queue for user-submitted reports (harassment, fake profile, abuse, spam…).
 * Filter by status and category, read the full report, resolve it with notes, and — when
 * a report is substantiated — block the reported user directly from the resolve dialog.
 *
 * This is a companionship marketplace: keeping the community safe (18+, public-place
 * meetings, companionship-only) depends on these complaints being actioned quickly.
 *
 * Backed by (docs/API.md → ADMIN API):
 *   GET  /admin/reports?status=&page=&limit=
 *   POST /admin/reports/:id/resolve   { resolutionNotes }
 *   POST /admin/users/:id/block       { reason }
 */

import { useMemo, useState } from 'react';
import {
  AlertTriangle,
  Ban,
  CheckCircle2,
  Flag,
  ShieldOff,
  User as UserIcon,
} from 'lucide-react';
import { PageHeader } from '@/components/ui/PageHeader';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { Select } from '@/components/ui/Select';
import { Badge, StatusBadge } from '@/components/ui/Badge';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { apiFetch, apiFetchList, ApiError } from '@/lib/api';
import { formatDateTime } from '@/lib/format';
import type { AdminReport, ReportCategory, ReportStatus } from '@/lib/types';
import useSWR from 'swr';

const PAGE_SIZE = 20;

const STATUS_OPTIONS: { label: string; value: '' | ReportStatus }[] = [
  { label: 'All statuses', value: '' },
  { label: 'Open', value: 'OPEN' },
  { label: 'Reviewing', value: 'REVIEWING' },
  { label: 'Resolved', value: 'RESOLVED' },
  { label: 'Dismissed', value: 'DISMISSED' },
];

const CATEGORY_OPTIONS: { label: string; value: '' | ReportCategory }[] = [
  { label: 'All categories', value: '' },
  { label: 'Harassment', value: 'HARASSMENT' },
  { label: 'Fake profile', value: 'FAKE_PROFILE' },
  { label: 'Abuse', value: 'ABUSE' },
  { label: 'Spam', value: 'SPAM' },
  { label: 'Other', value: 'OTHER' },
];

const CATEGORY_LABEL: Record<ReportCategory, string> = {
  HARASSMENT: 'Harassment',
  FAKE_PROFILE: 'Fake profile',
  ABUSE: 'Abuse',
  SPAM: 'Spam',
  OTHER: 'Other',
};

const CATEGORY_TONE: Record<ReportCategory, 'red' | 'amber' | 'gray'> = {
  HARASSMENT: 'red',
  ABUSE: 'red',
  FAKE_PROFILE: 'amber',
  SPAM: 'amber',
  OTHER: 'gray',
};

interface ReportListResponse {
  data: AdminReport[];
  meta?: { total: number };
}

export default function ComplaintsPage() {
  const [status, setStatus] = useState<'' | ReportStatus>('OPEN');
  const [category, setCategory] = useState<'' | ReportCategory>('');
  const [page, setPage] = useState(1);

  // Detail + resolve modal.
  const [active, setActive] = useState<AdminReport | null>(null);
  const [notes, setNotes] = useState('');
  const [alsoBan, setAlsoBan] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [modalError, setModalError] = useState<string | null>(null);

  const swrKey = useMemo(() => {
    const p = new URLSearchParams();
    p.set('page', String(page));
    p.set('limit', String(PAGE_SIZE));
    if (status) p.set('status', status);
    return `/reports?${p.toString()}`;
  }, [status, page]);

  const { data, isLoading, error, mutate } = useSWR<ReportListResponse>(
    swrKey,
    (path: string) =>
      apiFetchList<AdminReport[]>(path).then((r) => ({ data: r.data ?? [], meta: r.meta })),
    { revalidateOnFocus: false, keepPreviousData: true },
  );

  // `category` is filtered client-side (the admin reports list is keyed on status).
  const allRows = data?.data ?? [];
  const rows = category ? allRows.filter((r) => r.category === category) : allRows;
  const total = data?.meta?.total ?? allRows.length;

  function openReport(report: AdminReport) {
    setActive(report);
    setNotes(report.resolutionNotes ?? '');
    setAlsoBan(false);
    setModalError(null);
  }

  function closeModal() {
    if (submitting) return;
    setActive(null);
  }

  const isClosed = active?.status === 'RESOLVED' || active?.status === 'DISMISSED';

  async function submitResolution() {
    if (!active) return;
    const trimmed = notes.trim();
    if (!trimmed) {
      setModalError('Resolution notes are required.');
      return;
    }
    setSubmitting(true);
    setModalError(null);
    try {
      await apiFetch(`/reports/${active.id}/resolve`, {
        method: 'POST',
        body: { resolutionNotes: trimmed },
      });
      if (alsoBan && active.reportedUserId) {
        await apiFetch(`/users/${active.reportedUserId}/block`, {
          method: 'POST',
          body: { reason: `Report ${active.id} upheld: ${trimmed}` },
        });
      }
      setActive(null);
      await mutate();
    } catch (err) {
      setModalError(err instanceof ApiError ? err.message : 'Failed to resolve the complaint.');
    } finally {
      setSubmitting(false);
    }
  }

  const columns: Column<AdminReport>[] = [
    {
      key: 'category',
      header: 'Category',
      render: (r) => (
        <Badge tone={CATEGORY_TONE[r.category]} dot>
          {CATEGORY_LABEL[r.category]}
        </Badge>
      ),
    },
    {
      key: 'reportedUser',
      header: 'Reported',
      render: (r) => (
        <PartyCell
          name={r.reportedUser?.fullName}
          subtitle={r.reportedUser?.mobileNumber}
          role={r.reportedUser?.role}
        />
      ),
    },
    {
      key: 'reporter',
      header: 'Reporter',
      hideOnMobile: true,
      render: (r) => (
        <PartyCell
          name={r.reporter?.fullName}
          subtitle={r.reporter?.mobileNumber}
          role={r.reporter?.role}
        />
      ),
    },
    {
      key: 'description',
      header: 'Description',
      hideOnMobile: true,
      render: (r) => (
        <span className="line-clamp-2 max-w-xs text-slate-600">
          {r.description?.trim() || '—'}
        </span>
      ),
    },
    {
      key: 'createdAt',
      header: 'Filed',
      hideOnMobile: true,
      accessor: (r) => <span className="text-slate-500">{formatDateTime(r.createdAt)}</span>,
    },
    {
      key: 'status',
      header: 'Status',
      align: 'center',
      render: (r) => <StatusBadge status={r.status} />,
    },
    {
      key: 'actions',
      header: 'Actions',
      align: 'right',
      render: (r) => {
        const closed = r.status === 'RESOLVED' || r.status === 'DISMISSED';
        return (
          <Button
            size="sm"
            variant={closed ? 'outline' : 'primary'}
            leftIcon={
              closed ? (
                <CheckCircle2 className="h-3.5 w-3.5" />
              ) : (
                <Flag className="h-3.5 w-3.5" />
              )
            }
            onClick={(e) => {
              e.stopPropagation();
              openReport(r);
            }}
          >
            {closed ? 'View' : 'Resolve'}
          </Button>
        );
      },
    },
  ];

  return (
    <div>
      <PageHeader
        eyebrow="Trust & Safety"
        title="Complaints"
        description="Review and resolve reports from users. Substantiated complaints can ban the reported account."
      />

      {/* Filters */}
      <Card className="mb-4">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
          <Select
            label="Status"
            value={status}
            onChange={(e) => {
              setStatus(e.target.value as '' | ReportStatus);
              setPage(1);
            }}
            options={STATUS_OPTIONS}
            containerClassName="w-full sm:w-48"
          />
          <Select
            label="Category"
            value={category}
            onChange={(e) => {
              setCategory(e.target.value as '' | ReportCategory);
              setPage(1);
            }}
            options={CATEGORY_OPTIONS}
            containerClassName="w-full sm:w-48"
          />
          <div className="flex items-center gap-2 sm:ml-auto sm:pb-0.5">
            <AlertTriangle className="h-4 w-4 text-amber-500" />
            <span className="text-xs text-slate-500">
              Open reports should be actioned within 24 hours.
            </span>
          </div>
        </div>
      </Card>

      {error ? (
        <Card className="rounded-md border-2 border-ink bg-rose-50/60">
          <p className="text-sm text-rose-700">
            Couldn&rsquo;t load complaints. {(error as Error)?.message}
          </p>
        </Card>
      ) : (
        <DataTable
          columns={columns}
          rows={rows}
          rowKey={(r) => r.id}
          loading={isLoading}
          emptyMessage="No complaints match these filters."
          emptyIcon={<Flag className="h-8 w-8" />}
          onRowClick={openReport}
          pagination={{ page, limit: PAGE_SIZE, total, onPageChange: setPage }}
        />
      )}

      {/* Detail + resolve modal */}
      <Modal
        open={Boolean(active)}
        onClose={closeModal}
        dismissible={!submitting}
        size="lg"
        title={active ? CATEGORY_LABEL[active.category] + ' report' : 'Report'}
        description={
          active
            ? `Filed ${formatDateTime(active.createdAt)}`
            : undefined
        }
        footer={
          <>
            <Button variant="ghost" onClick={() => setActive(null)} disabled={submitting}>
              Close
            </Button>
            {!isClosed && (
              <Button
                variant="primary"
                loading={submitting}
                onClick={submitResolution}
                leftIcon={<CheckCircle2 className="h-4 w-4" />}
              >
                {alsoBan ? 'Resolve & ban' : 'Resolve complaint'}
              </Button>
            )}
          </>
        }
      >
        {active && (
          <div className="space-y-4">
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <DetailParty
                label="Reported user"
                name={active.reportedUser?.fullName}
                subtitle={active.reportedUser?.mobileNumber}
                role={active.reportedUser?.role}
                tone="rose"
              />
              <DetailParty
                label="Reported by"
                name={active.reporter?.fullName}
                subtitle={active.reporter?.mobileNumber}
                role={active.reporter?.role}
                tone="slate"
              />
            </div>

            <div className="flex items-center gap-2">
              <Badge tone={CATEGORY_TONE[active.category]} dot>
                {CATEGORY_LABEL[active.category]}
              </Badge>
              <StatusBadge status={active.status} />
              {active.bookingId && (
                <Badge tone="blue">Booking #{active.bookingId.slice(0, 8)}</Badge>
              )}
            </div>

            <div>
              <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-slate-400">
                Reporter&rsquo;s description
              </p>
              <p className="whitespace-pre-wrap rounded-md border-2 border-ink bg-white p-3 text-sm text-slate-700">
                {active.description?.trim() || 'No description provided.'}
              </p>
            </div>

            {isClosed ? (
              <div>
                <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-slate-400">
                  Resolution notes
                </p>
                <p className="whitespace-pre-wrap rounded-md border-2 border-ink bg-emerald-50 p-3 text-sm text-emerald-800">
                  {active.resolutionNotes?.trim() || '—'}
                </p>
                {active.resolvedAt && (
                  <p className="mt-1.5 text-xs text-slate-400">
                    Resolved {formatDateTime(active.resolvedAt)}
                  </p>
                )}
              </div>
            ) : (
              <div>
                <label className="mb-1.5 block text-sm font-medium text-slate-700">
                  Resolution notes
                </label>
                <textarea
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  rows={3}
                  autoFocus
                  placeholder="e.g. Contacted both parties; warning issued. No safety risk found."
                  className="w-full rounded-md border-2 border-ink bg-white p-3 text-sm text-slate-900 transition-colors focus:border-brand-500 focus:ring-2 focus:ring-brand-500/50"
                />

                <label className="mt-3 flex cursor-pointer items-start gap-2.5 rounded-md border-2 border-ink bg-rose-50/70 p-3">
                  <input
                    type="checkbox"
                    checked={alsoBan}
                    onChange={(e) => setAlsoBan(e.target.checked)}
                    className="mt-0.5 h-4 w-4 rounded border-2 border-ink text-brand-600 focus:ring-brand-500/50"
                  />
                  <span className="text-sm">
                    <span className="flex items-center gap-1.5 font-medium text-rose-700">
                      <Ban className="h-4 w-4" /> Ban the reported user
                    </span>
                    <span className="mt-0.5 block text-xs text-rose-600">
                      They lose access immediately; a companion listing is suspended too. Use only
                      for confirmed safety violations.
                    </span>
                  </span>
                </label>

                <div className="mt-3 flex items-start gap-2.5 rounded-md border-2 border-ink bg-slate-50 px-3 py-2.5">
                  <ShieldOff className="mt-0.5 h-4 w-4 shrink-0 text-slate-400" />
                  <p className="text-xs text-slate-500">
                    Resolving records your notes and closes the complaint. This action is logged
                    against your admin account.
                  </p>
                </div>
              </div>
            )}

            {modalError && <p className="text-xs text-rose-600">{modalError}</p>}
          </div>
        )}
      </Modal>
    </div>
  );
}

function PartyCell({
  name,
  subtitle,
  role,
}: {
  name?: string | null;
  subtitle?: string | null;
  role?: string;
}) {
  const initial = (name || '?').charAt(0).toUpperCase();
  return (
    <div className="flex items-center gap-2.5">
      <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full border-2 border-ink bg-brand-50 text-xs font-semibold text-brand-700 shadow-brutal-xs">
        {initial}
      </span>
      <div className="min-w-0">
        <p className="truncate text-sm font-medium text-slate-900">{name || 'Unknown'}</p>
        <p className="truncate text-xs text-slate-500">
          {subtitle || '—'}
          {role ? ` · ${role.charAt(0) + role.slice(1).toLowerCase()}` : ''}
        </p>
      </div>
    </div>
  );
}

function DetailParty({
  label,
  name,
  subtitle,
  role,
  tone,
}: {
  label: string;
  name?: string | null;
  subtitle?: string | null;
  role?: string;
  tone: 'rose' | 'slate';
}) {
  const ring = tone === 'rose' ? 'bg-rose-50/50' : 'bg-slate-50';
  const chip = tone === 'rose' ? 'bg-rose-100 text-rose-700' : 'bg-brand-100 text-brand-700';
  return (
    <div className={`rounded-md border-2 border-ink p-3 shadow-brutal ${ring}`}>
      <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400">{label}</p>
      <div className="flex items-center gap-2.5">
        <span
          className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-full border-2 border-ink text-sm font-semibold ${chip}`}
        >
          {(name || '?').charAt(0).toUpperCase()}
        </span>
        <div className="min-w-0">
          <p className="truncate text-sm font-medium text-slate-900">{name || 'Unknown'}</p>
          <p className="flex items-center gap-1 truncate text-xs text-slate-500">
            <UserIcon className="h-3 w-3" />
            {subtitle || '—'}
            {role ? ` · ${role.charAt(0) + role.slice(1).toLowerCase()}` : ''}
          </p>
        </div>
      </div>
    </div>
  );
}

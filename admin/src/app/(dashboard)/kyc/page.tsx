'use client';

/**
 * Admin → KYC queue
 *
 * Review queue for companion KYC documents (GOVERNMENT_ID + SELFIE). Each row is a
 * single document; admins preview the image and approve or reject it. Approving both
 * required documents auto-approves the companion profile (handled server-side).
 *
 * Backed by:
 *   GET  /admin/kyc?status=PENDING&page=&limit=
 *   POST /admin/kyc/:id/approve
 *   POST /admin/kyc/:id/reject  { reason }
 *
 * Note: the backend's default KYC list returns PENDING + SUBMITTED docs awaiting review.
 */

import { useMemo, useState } from 'react';
import Link from 'next/link';
import useSWR from 'swr';
import {
  CheckCircle2,
  FileCheck2,
  IdCard,
  ScanFace,
  ShieldCheck,
  XCircle,
} from 'lucide-react';
import { PageHeader } from '@/components/ui/PageHeader';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { Select } from '@/components/ui/Select';
import { Badge, StatusBadge } from '@/components/ui/Badge';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { apiFetch, apiFetchList, ApiError } from '@/lib/api';
import { formatDateTime, timeAgo } from '@/lib/format';
import type { AdminKycDocument } from '@/lib/types';

const PAGE_SIZE = 20;

const STATUS_OPTIONS = [
  { label: 'Pending review', value: 'PENDING' },
  { label: 'Submitted', value: 'SUBMITTED' },
  { label: 'Approved', value: 'APPROVED' },
  { label: 'Rejected', value: 'REJECTED' },
];

interface KycListResponse {
  data: AdminKycDocument[];
  meta?: { total: number };
}

export default function KycPage() {
  const [status, setStatus] = useState('PENDING');
  const [page, setPage] = useState(1);

  const [busyId, setBusyId] = useState<string | null>(null);
  const [preview, setPreview] = useState<AdminKycDocument | null>(null);
  const [rejectDoc, setRejectDoc] = useState<AdminKycDocument | null>(null);
  const [reason, setReason] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const swrKey = useMemo(
    () => `/kyc?status=${status}&page=${page}&limit=${PAGE_SIZE}`,
    [status, page],
  );

  const { data, isLoading, error, mutate } = useSWR<KycListResponse>(
    swrKey,
    (path: string) =>
      apiFetchList<AdminKycDocument[]>(path).then((r) => ({
        data: r.data ?? [],
        meta: r.meta,
      })),
    { revalidateOnFocus: false, keepPreviousData: true },
  );

  const rows = data?.data ?? [];
  const total = data?.meta?.total ?? rows.length;

  async function runApprove(doc: AdminKycDocument) {
    setBusyId(doc.id);
    setActionError(null);
    try {
      await apiFetch(`/kyc/${doc.id}/approve`, { method: 'POST' });
      if (preview?.id === doc.id) setPreview(null);
      await mutate();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Failed to approve document.');
    } finally {
      setBusyId(null);
    }
  }

  function openReject(doc: AdminKycDocument) {
    setRejectDoc(doc);
    setReason('');
    setActionError(null);
  }

  async function confirmReject() {
    if (!rejectDoc) return;
    const trimmed = reason.trim();
    if (!trimmed) {
      setActionError('A reason is required.');
      return;
    }
    setSubmitting(true);
    setActionError(null);
    try {
      await apiFetch(`/kyc/${rejectDoc.id}/reject`, {
        method: 'POST',
        body: { reason: trimmed },
      });
      if (preview?.id === rejectDoc.id) setPreview(null);
      setRejectDoc(null);
      await mutate();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Failed to reject document.');
    } finally {
      setSubmitting(false);
    }
  }

  const reviewable = (s: string) => s === 'PENDING' || s === 'SUBMITTED';

  const columns: Column<AdminKycDocument>[] = [
    {
      key: 'doc',
      header: 'Document',
      render: (doc) => (
        <button
          type="button"
          onClick={() => setPreview(doc)}
          className="flex items-center gap-3 text-left"
        >
          <span className="h-12 w-16 shrink-0 overflow-hidden rounded-md border-2 border-ink bg-slate-50 shadow-brutal-xs">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={doc.documentUrl}
              alt={docTypeLabel(doc.docType)}
              className="h-full w-full object-cover"
            />
          </span>
          <span className="min-w-0">
            <span className="flex items-center gap-1.5 font-medium text-slate-900">
              <DocIcon type={doc.docType} />
              {docTypeLabel(doc.docType)}
            </span>
            {doc.documentNumber && (
              <span className="block truncate text-xs text-slate-400">
                No. {doc.documentNumber}
              </span>
            )}
          </span>
        </button>
      ),
    },
    {
      key: 'user',
      header: 'Companion',
      render: (doc) => (
        <div className="min-w-0">
          <p className="truncate font-medium text-slate-800">
            {doc.user?.fullName ?? '—'}
          </p>
          <p className="truncate text-xs text-slate-500">{doc.user?.mobileNumber ?? '—'}</p>
        </div>
      ),
    },
    {
      key: 'submitted',
      header: 'Submitted',
      hideOnMobile: true,
      render: (doc) => (
        <span title={formatDateTime(doc.createdAt)} className="text-slate-500">
          {timeAgo(doc.createdAt)}
        </span>
      ),
    },
    {
      key: 'status',
      header: 'Status',
      align: 'center',
      render: (doc) => <StatusBadge status={doc.status} />,
    },
    {
      key: 'actions',
      header: 'Actions',
      align: 'right',
      render: (doc) =>
        reviewable(doc.status) ? (
          <div className="flex items-center justify-end gap-1.5">
            <Button
              size="sm"
              variant="success"
              loading={busyId === doc.id}
              onClick={() => runApprove(doc)}
              leftIcon={<CheckCircle2 className="h-3.5 w-3.5" />}
            >
              Approve
            </Button>
            <Button
              size="sm"
              variant="outline"
              onClick={() => openReject(doc)}
              leftIcon={<XCircle className="h-3.5 w-3.5" />}
            >
              Reject
            </Button>
          </div>
        ) : (
          <Button size="sm" variant="ghost" onClick={() => setPreview(doc)}>
            View
          </Button>
        ),
    },
  ];

  return (
    <div>
      <PageHeader
        eyebrow="Verification"
        title="KYC Queue"
        description="Verify companion identity documents. A companion goes live only after both government ID and selfie are approved."
        actions={
          <Select
            aria-label="KYC status filter"
            value={status}
            onChange={(e) => {
              setStatus(e.target.value);
              setPage(1);
            }}
            options={STATUS_OPTIONS}
            className="w-48"
          />
        }
      />

      {/* Safety reminder banner */}
      <div className="mb-4 flex items-start gap-3 rounded-md border-2 border-ink bg-acid px-4 py-3 shadow-brutal">
        <ShieldCheck className="mt-0.5 h-5 w-5 shrink-0 text-ink" />
        <p className="text-sm font-bold text-ink">
          Approve only genuine, legible documents where the selfie matches the ID. KYC keeps the
          companionship marketplace safe and 18+ only.
        </p>
      </div>

      {actionError && !rejectDoc && (
        <Card className="mb-4 border-2 border-ink bg-rose-50/70">
          <p className="text-sm text-rose-700">{actionError}</p>
        </Card>
      )}

      {error ? (
        <Card className="border-2 border-ink bg-rose-50/60">
          <p className="text-sm text-rose-700">
            Couldn’t load the KYC queue. {(error as Error)?.message}
          </p>
        </Card>
      ) : (
        <DataTable
          columns={columns}
          rows={rows}
          rowKey={(d) => d.id}
          loading={isLoading}
          emptyIcon={<FileCheck2 className="h-8 w-8" />}
          emptyMessage="No documents to review here. The queue is clear."
          pagination={{ page, limit: PAGE_SIZE, total, onPageChange: setPage }}
        />
      )}

      {/* Preview modal */}
      <Modal
        open={Boolean(preview)}
        onClose={() => setPreview(null)}
        size="xl"
        title={preview ? docTypeLabel(preview.docType) : 'Document'}
        description={preview?.user?.fullName ? `${preview.user.fullName}` : undefined}
        footer={
          preview && reviewable(preview.status) ? (
            <>
              <Button
                variant="outline"
                onClick={() => {
                  const d = preview;
                  setPreview(null);
                  if (d) openReject(d);
                }}
                leftIcon={<XCircle className="h-4 w-4" />}
              >
                Reject
              </Button>
              <Button
                variant="success"
                loading={busyId === preview.id}
                onClick={() => runApprove(preview)}
                leftIcon={<CheckCircle2 className="h-4 w-4" />}
              >
                Approve
              </Button>
            </>
          ) : undefined
        }
      >
        {preview && (
          <div className="space-y-3">
            <div className="overflow-hidden rounded-md border-2 border-ink bg-white shadow-brutal">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={preview.documentUrl}
                alt={docTypeLabel(preview.docType)}
                className="mx-auto max-h-[55vh] w-auto object-contain"
              />
            </div>
            <div className="flex flex-wrap items-center justify-between gap-2 text-sm">
              <div className="flex items-center gap-2">
                <StatusBadge status={preview.status} />
                {preview.documentNumber && (
                  <Badge tone="gray">No. {preview.documentNumber}</Badge>
                )}
              </div>
              <span className="text-slate-400">Submitted {formatDateTime(preview.createdAt)}</span>
            </div>
            {preview.user?.id && (
              <Link
                href={`/users/${preview.user.id}`}
                className="inline-block text-sm font-medium text-brand-600 hover:text-brand-700"
              >
                View companion account →
              </Link>
            )}
          </div>
        )}
      </Modal>

      {/* Reject reason modal */}
      <Modal
        open={Boolean(rejectDoc)}
        onClose={() => (submitting ? null : setRejectDoc(null))}
        dismissible={!submitting}
        title="Reject document"
        description={
          rejectDoc
            ? `${docTypeLabel(rejectDoc.docType)} for ${rejectDoc.user?.fullName ?? 'this companion'}. They will be asked to re-submit.`
            : undefined
        }
        footer={
          <>
            <Button variant="ghost" onClick={() => setRejectDoc(null)} disabled={submitting}>
              Cancel
            </Button>
            <Button variant="danger" loading={submitting} onClick={confirmReject}>
              Reject
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
          placeholder="e.g. Document is blurry / does not match selfie."
          className="w-full rounded-md border-2 border-ink bg-white p-3 text-sm text-slate-900 transition-colors focus:ring-2 focus:ring-brand-500/50"
        />
        {actionError && rejectDoc && <p className="mt-2 text-xs text-rose-600">{actionError}</p>}
      </Modal>
    </div>
  );
}

function docTypeLabel(t: string) {
  return t === 'GOVERNMENT_ID' ? 'Government ID' : t === 'SELFIE' ? 'Selfie' : t;
}

function DocIcon({ type }: { type: string }) {
  if (type === 'SELFIE') return <ScanFace className="h-4 w-4 text-slate-400" />;
  return <IdCard className="h-4 w-4 text-slate-400" />;
}

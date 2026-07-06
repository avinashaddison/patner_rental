'use client';

/**
 * Admin → Companion detail
 *
 * Full profile: bio, languages/interests, categories, photos, weekly availability,
 * wallet snapshot, and KYC documents (government ID + selfie) with preview. Admin can
 * approve / reject / suspend / feature directly from here.
 *
 * Backed by:
 *   GET  /admin/companions/:id          (detail incl. KYC)
 *   POST /admin/companions/:id/approve
 *   POST /admin/companions/:id/reject   { reason }
 *   POST /admin/companions/:id/suspend  { reason }
 *   POST /admin/companions/:id/feature  { isFeatured }
 */

import { useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import useSWR from 'swr';
import {
  ArrowLeft,
  BadgeCheck,
  Ban,
  CheckCircle2,
  Clock,
  IdCard,
  IndianRupee,
  Languages,
  MapPin,
  ScanFace,
  ShieldCheck,
  ShieldX,
  Sparkles,
  Star,
  Tag,
  Upload,
  XCircle,
} from 'lucide-react';
import { PageHeader } from '@/components/ui/PageHeader';
import { Card, CardHeader } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { Modal } from '@/components/ui/Modal';
import { Badge, StatusBadge } from '@/components/ui/Badge';
import { LoadingState } from '@/components/ui/Spinner';
import { swrFetcher, apiFetch, ApiError, ADMIN_API_BASE, getToken } from '@/lib/api';
import { formatINR, formatDate, formatDateTime } from '@/lib/format';
import type { AdminCompanion, AdminKycDocument } from '@/lib/types';

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

type ReasonKind = 'reject' | 'suspend';

export default function CompanionDetailPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const id = params?.id;

  const { data, isLoading, error, mutate } = useSWR<AdminCompanion>(
    id ? `/companions/${id}` : null,
    swrFetcher,
    { revalidateOnFocus: false },
  );

  const [busy, setBusy] = useState(false);
  const [reasonKind, setReasonKind] = useState<ReasonKind | null>(null);
  const [reason, setReason] = useState('');
  const [actionError, setActionError] = useState<string | null>(null);
  const [preview, setPreview] = useState<AdminKycDocument | null>(null);

  async function runSimpleAction(path: string, body?: Record<string, unknown>) {
    if (!id) return;
    setBusy(true);
    setActionError(null);
    try {
      await apiFetch(`/companions/${id}/${path}`, {
        method: 'POST',
        body,
      });
      await mutate();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Action failed.');
    } finally {
      setBusy(false);
    }
  }

  async function confirmReason() {
    if (!id || !reasonKind) return;
    const trimmed = reason.trim();
    if (!trimmed) {
      setActionError('A reason is required.');
      return;
    }
    setBusy(true);
    setActionError(null);
    try {
      await apiFetch(`/companions/${id}/${reasonKind}`, {
        method: 'POST',
        body: { reason: trimmed },
      });
      setReasonKind(null);
      setReason('');
      await mutate();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Action failed.');
    } finally {
      setBusy(false);
    }
  }

  if (isLoading) return <LoadingState label="Loading companion…" />;

  if (error || !data) {
    return (
      <div>
        <BackLink />
        <Card className="border-2 border-ink bg-rose-50/60">
          <p className="text-sm text-rose-700">
            Couldn’t load this companion. {(error as Error)?.message ?? 'Not found.'}
          </p>
        </Card>
      </div>
    );
  }

  const c = data;
  const name = c.name ?? c.user?.fullName ?? 'Unnamed companion';
  const docs = c.kyc?.documents ?? c.user?.kycDocuments ?? [];

  return (
    <div>
      <BackLink />

      <PageHeader
        eyebrow="Companion"
        title={name}
        description={c.user?.mobileNumber ? `Mobile ${c.user.mobileNumber}` : undefined}
        actions={
          <div className="flex flex-wrap items-center gap-2">
            {c.status === 'PENDING' && (
              <Button
                variant="success"
                loading={busy}
                onClick={() => runSimpleAction('approve')}
                leftIcon={<CheckCircle2 className="h-4 w-4" />}
              >
                Approve
              </Button>
            )}
            {(c.status === 'REJECTED' || c.status === 'SUSPENDED') && (
              <Button
                variant="success"
                loading={busy}
                onClick={() => runSimpleAction('approve')}
                leftIcon={<BadgeCheck className="h-4 w-4" />}
              >
                Re-approve
              </Button>
            )}
            {c.status === 'APPROVED' && (
              <Button
                variant={c.isFeatured ? 'secondary' : 'outline'}
                loading={busy}
                onClick={() => runSimpleAction('feature', { isFeatured: !c.isFeatured })}
                leftIcon={<Sparkles className="h-4 w-4" />}
              >
                {c.isFeatured ? 'Unfeature' : 'Feature'}
              </Button>
            )}
            {c.status === 'APPROVED' && (
              <Button
                variant="outline"
                onClick={() => {
                  setReasonKind('suspend');
                  setReason('');
                  setActionError(null);
                }}
                leftIcon={<Ban className="h-4 w-4" />}
              >
                Suspend
              </Button>
            )}
            {c.status === 'PENDING' && (
              <Button
                variant="danger"
                onClick={() => {
                  setReasonKind('reject');
                  setReason('');
                  setActionError(null);
                }}
                leftIcon={<XCircle className="h-4 w-4" />}
              >
                Reject
              </Button>
            )}
          </div>
        }
      />

      {/* Status strip */}
      <div className="mb-6 flex flex-wrap items-center gap-2">
        <StatusBadge status={c.status} />
        {c.isFeatured && (
          <Badge tone="purple">
            <Sparkles className="h-3 w-3" /> Featured
          </Badge>
        )}
        <Badge tone={c.kyc?.approved || c.isVerified ? 'green' : 'amber'}>
          {c.kyc?.approved || c.isVerified ? (
            <ShieldCheck className="h-3 w-3" />
          ) : (
            <ShieldX className="h-3 w-3" />
          )}
          {c.kyc?.approved || c.isVerified ? 'KYC verified' : 'KYC pending'}
        </Badge>
        <Badge tone={c.isOnline ? 'green' : 'gray'} dot>
          {c.isOnline ? 'Online' : 'Offline'}
        </Badge>
      </div>

      {actionError && reasonKind === null && (
        <Card className="mb-4 border-2 border-ink bg-rose-50/70">
          <p className="text-sm text-rose-700">{actionError}</p>
        </Card>
      )}

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        {/* Left: profile + KYC */}
        <div className="space-y-6 lg:col-span-2">
          {/* About */}
          <Card>
            <CardHeader title="About" />
            <p className="text-sm leading-relaxed text-slate-700">
              {c.aboutMe?.trim() || 'No bio provided.'}
            </p>

            <div className="mt-5 grid grid-cols-1 gap-4 sm:grid-cols-2">
              <InfoRow icon={<MapPin className="h-4 w-4" />} label="City" value={c.city || '—'} />
              <InfoRow
                icon={<IndianRupee className="h-4 w-4" />}
                label="Hourly rate"
                value={formatINR(c.hourlyRate)}
              />
              <InfoRow
                icon={<Star className="h-4 w-4" />}
                label="Rating"
                value={`${(c.ratingAvg ?? 0).toFixed(1)} (${c.ratingCount ?? 0})`}
              />
              <InfoRow
                icon={<BadgeCheck className="h-4 w-4" />}
                label="Total bookings"
                value={String(c.totalBookings ?? 0)}
              />
              <InfoRow
                icon={<Languages className="h-4 w-4" />}
                label="Languages"
                value={c.languages?.length ? c.languages.join(', ') : '—'}
              />
              <InfoRow
                icon={<Tag className="h-4 w-4" />}
                label="Interests"
                value={c.interests?.length ? c.interests.join(', ') : '—'}
              />
            </div>

            {c.categories && c.categories.length > 0 && (
              <div className="mt-5">
                <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Activity categories
                </p>
                <div className="flex flex-wrap gap-2">
                  {c.categories.map((cat) => (
                    <Badge key={cat.id} tone="brand">
                      {cat.name}
                    </Badge>
                  ))}
                </div>
              </div>
            )}

            {c.rejectedReason && (c.status === 'REJECTED' || c.status === 'SUSPENDED') && (
              <div className="mt-5 rounded-md border-2 border-ink bg-rose-50/70 p-3">
                <p className="text-xs font-semibold uppercase tracking-wide text-rose-600">
                  {c.status === 'REJECTED' ? 'Rejection reason' : 'Suspension reason'}
                </p>
                <p className="mt-1 text-sm text-rose-700">{c.rejectedReason}</p>
              </div>
            )}
          </Card>

          {/* Photos */}
          <Card>
            <CardHeader
              title="Profile photos"
              subtitle={`${c.photos?.length ?? 0} uploaded`}
            />
            {c.photos && c.photos.length > 0 ? (
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                {c.photos.map((p) => (
                  <div
                    key={p.id}
                    className="group relative aspect-[3/4] overflow-hidden rounded-md border-2 border-ink"
                  >
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={p.photoUrl}
                      alt="Companion"
                      className="h-full w-full object-cover transition-transform group-hover:scale-105"
                    />
                    {p.isPrimary && (
                      <span className="absolute left-2 top-2 rounded-full border-2 border-ink bg-brand-500 px-2 py-0.5 text-[10px] font-bold text-white">
                        Primary
                      </span>
                    )}
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-sm text-slate-400">No photos uploaded.</p>
            )}
          </Card>

          {/* KYC documents */}
          <Card>
            <CardHeader
              title="KYC documents"
              subtitle="Government ID + selfie verification (required to go live)"
              action={
                <Badge tone={c.kyc?.approved ? 'green' : 'amber'}>
                  {c.kyc?.approved ? 'Approved' : 'Pending'}
                </Badge>
              }
            />
            {docs.length > 0 ? (
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                {docs.map((doc) => (
                  <KycDocCard key={doc.id} doc={doc} onPreview={() => setPreview(doc)} />
                ))}
              </div>
            ) : (
              <p className="text-sm text-slate-400">
                This companion has not submitted any KYC documents yet.
              </p>
            )}

            {/* Admin manual upload — onboard a companion whose docs were collected
                offline. Each upload is recorded as an approved, admin-verified doc. */}
            {id && <AdminKycUpload companionId={id} onUploaded={() => mutate()} />}
          </Card>
        </div>

        {/* Right: account + wallet + availability */}
        <div className="space-y-6">
          <Card>
            <CardHeader title="Account" />
            <dl className="space-y-3 text-sm">
              <KeyVal k="Name" v={c.user?.fullName ?? name} />
              <KeyVal k="Mobile" v={c.user?.mobileNumber ?? '—'} />
              <KeyVal k="Email" v={c.user?.email ?? '—'} />
              <KeyVal k="Age" v={c.age ? `${c.age} years` : '—'} />
              <KeyVal
                k="Account"
                v={
                  c.user?.isBlocked ? (
                    <Badge tone="red" dot>
                      Blocked
                    </Badge>
                  ) : (
                    <Badge tone="green" dot>
                      Active
                    </Badge>
                  )
                }
              />
              {c.user?.id && (
                <div className="pt-1">
                  <Link
                    href={`/users/${c.user.id}`}
                    className="text-sm font-medium text-brand-600 hover:text-brand-700"
                  >
                    View user account →
                  </Link>
                </div>
              )}
              <KeyVal k="Joined" v={formatDate(c.createdAt)} />
              {c.approvedAt && <KeyVal k="Approved" v={formatDateTime(c.approvedAt)} />}
            </dl>
          </Card>

          {c.user?.wallet && (
            <Card>
              <CardHeader title="Earnings wallet" />
              <dl className="space-y-3 text-sm">
                <KeyVal k="Balance" v={formatINR(c.user.wallet.balance)} />
                <KeyVal k="Pending" v={formatINR(c.user.wallet.pendingBalance)} />
                <KeyVal k="Total earned" v={formatINR(c.user.wallet.totalEarned)} />
                <KeyVal k="Withdrawn" v={formatINR(c.user.wallet.totalWithdrawn)} />
              </dl>
            </Card>
          )}

          <Card>
            <CardHeader title="Weekly availability" />
            {c.availability && c.availability.length > 0 ? (
              <ul className="space-y-2 text-sm">
                {c.availability.map((slot) => (
                  <li
                    key={slot.id}
                    className="flex items-center justify-between rounded-md border-2 border-ink bg-slate-50 px-3 py-2"
                  >
                    <span className="flex items-center gap-2 font-medium text-slate-700">
                      <Clock className="h-3.5 w-3.5 text-brand-400" />
                      {DAYS[slot.dayOfWeek] ?? `Day ${slot.dayOfWeek}`}
                    </span>
                    <span className="text-slate-600">
                      {slot.startTime} – {slot.endTime}
                    </span>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="text-sm text-slate-400">No availability set.</p>
            )}
          </Card>
        </div>
      </div>

      {/* Reason modal */}
      <Modal
        open={reasonKind !== null}
        onClose={() => (busy ? null : setReasonKind(null))}
        dismissible={!busy}
        title={reasonKind === 'reject' ? 'Reject companion' : 'Suspend companion'}
        description="The companion will be notified. This reason is recorded on the profile."
        footer={
          <>
            <Button variant="ghost" onClick={() => setReasonKind(null)} disabled={busy}>
              Cancel
            </Button>
            <Button variant="danger" loading={busy} onClick={confirmReason}>
              {reasonKind === 'reject' ? 'Reject' : 'Suspend'}
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
          className="w-full rounded-md border-2 border-ink bg-white p-3 text-sm text-slate-900 transition-colors focus:ring-2 focus:ring-brand-500/50"
        />
        {actionError && reasonKind !== null && (
          <p className="mt-2 text-xs text-rose-600">{actionError}</p>
        )}
      </Modal>

      {/* Document preview modal */}
      <Modal
        open={Boolean(preview)}
        onClose={() => setPreview(null)}
        size="xl"
        title={preview ? docTypeLabel(preview.docType) : 'Document'}
        description={preview?.documentNumber ? `No. ${preview.documentNumber}` : undefined}
      >
        {preview && (
          <div className="space-y-3">
            <div className="overflow-hidden rounded-md border-2 border-ink bg-slate-50">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={preview.documentUrl}
                alt={docTypeLabel(preview.docType)}
                className="mx-auto max-h-[60vh] w-auto object-contain"
              />
            </div>
            <div className="flex items-center justify-between">
              <StatusBadge status={preview.status} />
              <a
                href={preview.documentUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="text-sm font-medium text-brand-600 hover:text-brand-700"
              >
                Open original →
              </a>
            </div>
          </div>
        )}
      </Modal>
    </div>
  );
}

function BackLink() {
  return (
    <Link
      href="/companions"
      className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-slate-500 transition-colors hover:text-brand-600"
    >
      <ArrowLeft className="h-4 w-4" />
      Back to companions
    </Link>
  );
}

function docTypeLabel(t: string) {
  return t === 'GOVERNMENT_ID' ? 'Government ID' : t === 'SELFIE' ? 'Selfie' : t;
}

/**
 * Admin-side manual KYC upload. Lets an admin add a Government ID / Selfie for a
 * companion onboarded offline — the image is uploaded and the document is stored
 * as approved+admin-verified. Uploading both required docs auto-verifies KYC.
 * Posts multipart to `POST /admin/companions/:id/kyc` (field "image" + docType).
 */
function AdminKycUpload({
  companionId,
  onUploaded,
}: {
  companionId: string;
  onUploaded: () => void;
}) {
  const [docType, setDocType] = useState<'GOVERNMENT_ID' | 'SELFIE'>('GOVERNMENT_ID');
  const [documentNumber, setDocumentNumber] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [okMsg, setOkMsg] = useState<string | null>(null);

  async function onFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = ''; // allow re-picking the same file
    if (!file) return;
    if (!file.type.startsWith('image/')) {
      setError('Please choose an image file (photo/scan of the document).');
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      setError('Image must be under 5 MB.');
      return;
    }
    setBusy(true);
    setError(null);
    setOkMsg(null);
    try {
      const form = new FormData();
      form.append('image', file);
      form.append('docType', docType);
      if (documentNumber.trim()) form.append('documentNumber', documentNumber.trim());
      const res = await fetch(`${ADMIN_API_BASE}/companions/${companionId}/kyc`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${getToken() ?? ''}` },
        body: form,
      });
      if (!res.ok) {
        const body = (await res.json().catch(() => null)) as
          | { error?: { message?: string } }
          | null;
        throw new Error(body?.error?.message || `Upload failed (${res.status}).`);
      }
      setOkMsg(`${docTypeLabel(docType)} uploaded and approved.`);
      setDocumentNumber('');
      onUploaded();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Upload failed.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mt-5 rounded-xl border border-slate-200 bg-slate-50/70 p-4">
      <div className="mb-3 flex items-center gap-2">
        <Upload className="h-4 w-4 text-brand-600" />
        <p className="text-sm font-semibold text-slate-800">Add a document (admin)</p>
      </div>
      <p className="mb-3 text-xs text-slate-500">
        For companions onboarded offline. The image you upload is stored as an
        approved, admin-verified document. Adding both a Government ID and a Selfie
        marks KYC as verified.
      </p>

      <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
        <div className="w-full sm:w-48">
          <label className="mb-1 block text-xs font-medium text-slate-600">Document type</label>
          <div className="flex gap-1 rounded-lg border border-slate-300 bg-white p-1">
            <button
              type="button"
              onClick={() => setDocType('GOVERNMENT_ID')}
              className={
                'flex flex-1 items-center justify-center gap-1 rounded-md px-2 py-1.5 text-xs font-medium ' +
                (docType === 'GOVERNMENT_ID'
                  ? 'bg-brand-600 text-white'
                  : 'text-slate-600 hover:bg-slate-50')
              }
            >
              <IdCard className="h-3.5 w-3.5" /> Gov ID
            </button>
            <button
              type="button"
              onClick={() => setDocType('SELFIE')}
              className={
                'flex flex-1 items-center justify-center gap-1 rounded-md px-2 py-1.5 text-xs font-medium ' +
                (docType === 'SELFIE'
                  ? 'bg-brand-600 text-white'
                  : 'text-slate-600 hover:bg-slate-50')
              }
            >
              <ScanFace className="h-3.5 w-3.5" /> Selfie
            </button>
          </div>
        </div>

        {docType === 'GOVERNMENT_ID' && (
          <Input
            label="ID number (optional)"
            value={documentNumber}
            onChange={(e) => setDocumentNumber(e.target.value)}
            placeholder="e.g. Aadhaar / PAN / DL no."
            containerClassName="flex-1"
          />
        )}

        <label className="shrink-0">
          <input
            type="file"
            accept="image/*"
            className="hidden"
            disabled={busy}
            onChange={onFile}
          />
          <span
            className={
              'inline-flex cursor-pointer items-center gap-2 rounded-xl px-4 py-2.5 text-sm font-semibold ' +
              (busy
                ? 'cursor-not-allowed bg-slate-200 text-slate-400'
                : 'bg-brand-600 text-white hover:bg-brand-700')
            }
          >
            <Upload className="h-4 w-4" />
            {busy ? 'Uploading…' : `Upload ${docTypeLabel(docType)}`}
          </span>
        </label>
      </div>

      {error && <p className="mt-2 text-xs text-rose-600">{error}</p>}
      {okMsg && <p className="mt-2 text-xs text-emerald-600">{okMsg}</p>}
    </div>
  );
}

function KycDocCard({
  doc,
  onPreview,
}: {
  doc: AdminKycDocument;
  onPreview: () => void;
}) {
  return (
    <div className="overflow-hidden rounded-md border-2 border-ink bg-white shadow-brutal">
      <button
        type="button"
        onClick={onPreview}
        className="block aspect-video w-full overflow-hidden border-b-2 border-ink bg-slate-50"
        aria-label={`Preview ${docTypeLabel(doc.docType)}`}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={doc.documentUrl}
          alt={docTypeLabel(doc.docType)}
          className="h-full w-full object-cover transition-transform hover:scale-105"
        />
      </button>
      <div className="flex items-center justify-between gap-2 px-3 py-2.5">
        <div className="min-w-0">
          <p className="truncate text-sm font-medium text-slate-800">
            {docTypeLabel(doc.docType)}
          </p>
          {doc.documentNumber && (
            <p className="truncate text-xs text-slate-400">No. {doc.documentNumber}</p>
          )}
        </div>
        <StatusBadge status={doc.status} />
      </div>
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
        <p className="truncate text-sm font-medium text-slate-800">{value}</p>
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

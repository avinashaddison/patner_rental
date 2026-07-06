'use client';

/**
 * Admin → Post detail
 *
 * Full record for a single companion photo post: the image gallery, caption,
 * status, like / comment counts, and the author (companion). Admin can
 * soft-remove a published post — it disappears from all feeds and the author
 * is notified.
 *
 * Backed by:
 *   GET    /admin/posts/:id
 *   DELETE /admin/posts/:id            (soft-remove → status REMOVED)
 */

import { useState } from 'react';
import { useParams } from 'next/navigation';
import Link from 'next/link';
import useSWR from 'swr';
import { ArrowLeft, Heart, ImageOff, MessageCircle, Trash2, User } from 'lucide-react';
import { PageHeader } from '@/components/ui/PageHeader';
import { Card, CardHeader } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { StatCard } from '@/components/ui/StatCard';
import { StatusBadge } from '@/components/ui/Badge';
import { LoadingState } from '@/components/ui/Spinner';
import { swrFetcher, apiFetch, ApiError } from '@/lib/api';
import { formatDateTime } from '@/lib/format';
import type { AdminPost } from '@/lib/types';

export default function PostDetailPage() {
  const params = useParams<{ id: string }>();
  const id = params?.id;

  const { data, isLoading, error, mutate } = useSWR<AdminPost>(
    id ? `/posts/${id}` : null,
    swrFetcher,
    { revalidateOnFocus: false },
  );

  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  function openRemove() {
    setConfirming(true);
    setActionError(null);
  }

  async function confirmRemove() {
    if (!id) return;
    setBusy(true);
    setActionError(null);
    try {
      await apiFetch(`/posts/${id}`, { method: 'DELETE' });
      setConfirming(false);
      await mutate();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Action failed.');
    } finally {
      setBusy(false);
    }
  }

  if (isLoading) return <LoadingState label="Loading post…" />;

  if (error || !data) {
    return (
      <div>
        <BackLink />
        <Card className="border-rose-200 bg-rose-50/60">
          <p className="text-sm text-rose-700">
            Couldn’t load this post. {(error as Error)?.message ?? 'Not found.'}
          </p>
        </Card>
      </div>
    );
  }

  const p = data;
  const companionName = p.companion?.name ?? 'Unknown companion';
  const canRemove = p.status === 'PUBLISHED';

  return (
    <div>
      <BackLink />

      <PageHeader
        eyebrow="Post"
        title={p.caption || 'No caption'}
        description={`Companion photo post · ${p.images.length} photo${p.images.length === 1 ? '' : 's'}`}
        actions={
          canRemove ? (
            <Button
              variant="danger"
              onClick={openRemove}
              leftIcon={<Trash2 className="h-4 w-4" />}
            >
              Remove post
            </Button>
          ) : undefined
        }
      />

      {/* Status strip */}
      <div className="mb-6 flex flex-wrap items-center gap-2">
        <StatusBadge status={p.status} />
      </div>

      {actionError && !confirming && (
        <Card className="mb-4 border-rose-200 bg-rose-50/70">
          <p className="text-sm text-rose-700">{actionError}</p>
        </Card>
      )}

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        {/* Left: gallery + caption */}
        <div className="space-y-6 lg:col-span-2">
          <Card>
            <CardHeader title="Photos" subtitle={`${p.images.length} in this post`} />
            {p.images.length > 0 ? (
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
                {p.images.map((url, i) => (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    key={`${url}-${i}`}
                    src={url}
                    alt={`Post photo ${i + 1}`}
                    className="aspect-square w-full rounded-xl object-cover ring-1 ring-slate-200"
                  />
                ))}
              </div>
            ) : (
              <div className="flex items-center gap-2 text-sm text-slate-400">
                <ImageOff className="h-4 w-4" />
                No photos attached to this post.
              </div>
            )}
          </Card>

          <Card>
            <CardHeader title="Caption" />
            <p className="text-sm text-slate-700">{p.caption || 'No caption.'}</p>
          </Card>
        </div>

        {/* Right: engagement + author */}
        <div className="space-y-6">
          <div className="grid grid-cols-2 gap-4">
            <StatCard
              label="Likes"
              value={p.likeCount}
              tone="rose"
              icon={<Heart className="h-5 w-5" />}
            />
            <StatCard
              label="Comments"
              value={p.commentCount}
              tone="sky"
              icon={<MessageCircle className="h-5 w-5" />}
            />
          </div>

          <Card>
            <CardHeader title="Companion" />
            <PartyBlock
              name={companionName}
              mobile={p.companion?.mobileNumber}
              href={p.companionId ? `/companions/${p.companionId}` : undefined}
              linkLabel="View companion →"
            />
          </Card>

          <Card>
            <CardHeader title="Details" />
            <dl className="space-y-3 text-sm">
              <KeyVal k="Status" v={<StatusBadge status={p.status} />} />
              <KeyVal k="Created" v={formatDateTime(p.createdAt)} />
              {p.updatedAt && <KeyVal k="Updated" v={formatDateTime(p.updatedAt)} />}
            </dl>
          </Card>
        </div>
      </div>

      {/* Remove modal */}
      <Modal
        open={confirming}
        onClose={() => (busy ? null : setConfirming(false))}
        dismissible={!busy}
        title="Remove post"
        description="This hides the post from all feeds (status REMOVED) and notifies the author. It does not delete the underlying images."
        footer={
          <>
            <Button variant="ghost" onClick={() => setConfirming(false)} disabled={busy}>
              Close
            </Button>
            <Button variant="danger" loading={busy} onClick={confirmRemove}>
              Remove post
            </Button>
          </>
        }
      >
        <div className="space-y-2 text-sm text-slate-600">
          <p>
            The post will no longer appear in any feed. The companion who posted it is
            notified that it was removed by moderation.
          </p>
          {p.caption && (
            <p className="rounded-lg bg-slate-50 p-2.5 text-slate-700">“{p.caption}”</p>
          )}
        </div>
        {actionError && confirming && <p className="mt-2 text-xs text-rose-600">{actionError}</p>}
      </Modal>
    </div>
  );
}

function BackLink() {
  return (
    <Link
      href="/posts"
      className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-slate-500 transition-colors hover:text-brand-600"
    >
      <ArrowLeft className="h-4 w-4" />
      Back to posts
    </Link>
  );
}

function PartyBlock({
  name,
  mobile,
  href,
  linkLabel,
}: {
  name: string;
  mobile?: string | null;
  href?: string;
  linkLabel: string;
}) {
  const initial = (name || '?').charAt(0).toUpperCase();
  return (
    <div>
      <div className="flex items-center gap-3">
        <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-brand-50 text-sm font-semibold text-brand-700">
          {initial}
        </span>
        <div className="min-w-0">
          <p className="truncate font-medium text-slate-900">{name}</p>
          <p className="truncate text-xs text-slate-500">{mobile || '—'}</p>
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

function KeyVal({ k, v }: { k: string; v: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <dt className="text-slate-500">{k}</dt>
      <dd className="text-right font-medium text-slate-800">{v}</dd>
    </div>
  );
}

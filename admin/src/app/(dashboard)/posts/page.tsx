'use client';

/**
 * Admin → Posts moderation
 *
 * Browse every companion photo post surfaced in the feeds. Filter by status,
 * search by caption / companion, and soft-remove a post directly from the row.
 * Removing hides the post from all feeds and notifies the author.
 *
 * Backed by:
 *   GET    /admin/posts?status=&q=&page=&limit=
 *   GET    /admin/posts/:id
 *   DELETE /admin/posts/:id            (soft-remove → status REMOVED)
 */

import { useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import useSWR from 'swr';
import { Heart, ImageOff, Images, MessageCircle, Search, Trash2 } from 'lucide-react';
import { PageHeader } from '@/components/ui/PageHeader';
import { Card } from '@/components/ui/Card';
import { Input } from '@/components/ui/Input';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { Select } from '@/components/ui/Select';
import { StatusBadge } from '@/components/ui/Badge';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { apiFetch, apiFetchList, ApiError } from '@/lib/api';
import { formatDate } from '@/lib/format';
import type { AdminPost } from '@/lib/types';

const PAGE_SIZE = 20;

const STATUS_OPTIONS = [
  { label: 'All statuses', value: '' },
  { label: 'Published', value: 'PUBLISHED' },
  { label: 'Removed', value: 'REMOVED' },
];

interface PostListResponse {
  data: AdminPost[];
  meta?: { total: number };
}

export default function PostsPage() {
  const router = useRouter();
  const [status, setStatus] = useState('');
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(1);

  const [target, setTarget] = useState<AdminPost | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [banner, setBanner] = useState<string | null>(null);

  const swrKey = useMemo(() => {
    const p = new URLSearchParams();
    p.set('page', String(page));
    p.set('limit', String(PAGE_SIZE));
    if (status) p.set('status', status);
    if (query) p.set('q', query);
    return `/posts?${p.toString()}`;
  }, [status, query, page]);

  const { data, isLoading, error, mutate } = useSWR<PostListResponse>(
    swrKey,
    (path: string) =>
      apiFetchList<AdminPost[]>(path).then((r) => ({ data: r.data ?? [], meta: r.meta })),
    { revalidateOnFocus: false, keepPreviousData: true },
  );

  const rows = data?.data ?? [];
  const total = data?.meta?.total ?? rows.length;

  function submitSearch(e: React.FormEvent) {
    e.preventDefault();
    setPage(1);
    setQuery(search.trim());
  }

  function openRemove(post: AdminPost) {
    setTarget(post);
    setActionError(null);
  }

  async function confirmRemove() {
    if (!target) return;
    setSubmitting(true);
    setActionError(null);
    try {
      await apiFetch(`/posts/${target.id}`, { method: 'DELETE' });
      setBanner('Post removed. It is now hidden from all feeds and the author has been notified.');
      setTarget(null);
      await mutate();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Action failed.');
    } finally {
      setSubmitting(false);
    }
  }

  const columns: Column<AdminPost>[] = [
    {
      key: 'post',
      header: 'Post',
      render: (p) => (
        <div className="flex min-w-0 items-center gap-3">
          {p.images[0] ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={p.images[0]}
              alt=""
              className="h-10 w-10 shrink-0 rounded-lg object-cover ring-1 ring-slate-200"
            />
          ) : (
            <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-slate-100 text-slate-400">
              <ImageOff className="h-4 w-4" />
            </span>
          )}
          <div className="min-w-0">
            <p className="truncate text-sm font-medium text-slate-800">
              {p.caption || 'No caption'}
            </p>
            <p className="truncate text-xs text-slate-500">
              {p.images.length} photo{p.images.length === 1 ? '' : 's'}
            </p>
          </div>
        </div>
      ),
    },
    {
      key: 'companion',
      header: 'Companion',
      hideOnMobile: true,
      render: (p) => (
        <PersonCell
          name={p.companion?.name}
          sub={p.companion?.mobileNumber}
          fallback="Unknown companion"
        />
      ),
    },
    {
      key: 'engagement',
      header: 'Engagement',
      hideOnMobile: true,
      render: (p) => (
        <div className="flex items-center gap-3 text-xs text-slate-600">
          <span className="inline-flex items-center gap-1">
            <Heart className="h-3.5 w-3.5 text-rose-500" /> {p.likeCount}
          </span>
          <span className="inline-flex items-center gap-1">
            <MessageCircle className="h-3.5 w-3.5 text-slate-400" /> {p.commentCount}
          </span>
        </div>
      ),
    },
    {
      key: 'created',
      header: 'Created',
      hideOnMobile: true,
      render: (p) => <span className="text-slate-700">{formatDate(p.createdAt)}</span>,
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
        const stop = (fn: () => void) => (e: React.MouseEvent) => {
          e.stopPropagation();
          fn();
        };
        if (p.status !== 'PUBLISHED') {
          return <span className="text-xs text-slate-400">Removed</span>;
        }
        return (
          <div className="flex items-center justify-end gap-2">
            <Button
              size="sm"
              variant="danger"
              onClick={stop(() => openRemove(p))}
              leftIcon={<Trash2 className="h-3.5 w-3.5" />}
            >
              Remove
            </Button>
          </div>
        );
      },
    },
  ];

  return (
    <div>
      <PageHeader
        eyebrow="Moderation"
        title="Posts"
        description="Every companion photo post surfaced in the feeds. Remove anything that breaks the guidelines — the author is notified."
      />

      {/* Filters */}
      <Card className="mb-4">
        <form onSubmit={submitSearch} className="flex flex-col gap-3 sm:flex-row sm:items-end">
          <Input
            label="Search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Caption or companion…"
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
        <Card className="mb-4 border-emerald-200 bg-emerald-50/70">
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
        <Card className="mb-4 border-rose-200 bg-rose-50/70">
          <p className="text-sm text-rose-700">{actionError}</p>
        </Card>
      )}

      {error ? (
        <Card className="border-rose-200 bg-rose-50/60">
          <p className="text-sm text-rose-700">
            Couldn’t load posts. {(error as Error)?.message}
          </p>
        </Card>
      ) : (
        <DataTable
          columns={columns}
          rows={rows}
          rowKey={(p) => p.id}
          loading={isLoading}
          emptyMessage="No posts match these filters."
          emptyIcon={<Images className="h-8 w-8" />}
          onRowClick={(p) => router.push(`/posts/${p.id}`)}
          pagination={{ page, limit: PAGE_SIZE, total, onPageChange: setPage }}
        />
      )}

      {/* Remove modal */}
      <Modal
        open={Boolean(target)}
        onClose={() => (submitting ? null : setTarget(null))}
        dismissible={!submitting}
        title="Remove post"
        description={
          target
            ? 'This hides the post from all feeds (status REMOVED) and notifies the author. It does not delete the underlying images.'
            : undefined
        }
        footer={
          <>
            <Button variant="ghost" onClick={() => setTarget(null)} disabled={submitting}>
              Close
            </Button>
            <Button variant="danger" loading={submitting} onClick={confirmRemove}>
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
          {target?.caption && (
            <p className="rounded-lg bg-slate-50 p-2.5 text-slate-700">“{target.caption}”</p>
          )}
        </div>
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

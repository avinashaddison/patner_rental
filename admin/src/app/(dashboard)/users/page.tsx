'use client';

/**
 * Admin → Users
 *
 * Search + filter all accounts (customers and companions). Filter by role and
 * blocked status, search by name / mobile / email / referral code, and block or
 * unblock from the row.
 *
 * Backed by:
 *   GET  /admin/users?role=&blocked=&q=&page=&limit=
 *   POST /admin/users/:id/block   { reason }
 *   POST /admin/users/:id/unblock
 */

import { useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import useSWR from 'swr';
import { Ban, CheckCircle2, Search, ShieldOff } from 'lucide-react';
import { PageHeader } from '@/components/ui/PageHeader';
import { Card } from '@/components/ui/Card';
import { Input } from '@/components/ui/Input';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { Select } from '@/components/ui/Select';
import { Badge } from '@/components/ui/Badge';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { apiFetch, apiFetchList, ApiError } from '@/lib/api';
import { formatDate } from '@/lib/format';
import type { AdminUser } from '@/lib/types';

const PAGE_SIZE = 20;

const ROLE_OPTIONS = [
  { label: 'All roles', value: '' },
  { label: 'Customers', value: 'CUSTOMER' },
  { label: 'Companions', value: 'COMPANION' },
  { label: 'Admins', value: 'ADMIN' },
];

const BLOCKED_OPTIONS = [
  { label: 'Active & blocked', value: '' },
  { label: 'Active only', value: 'false' },
  { label: 'Blocked only', value: 'true' },
];

const ROLE_TONE: Record<string, 'brand' | 'blue' | 'gray'> = {
  COMPANION: 'brand',
  CUSTOMER: 'blue',
  ADMIN: 'gray',
};

interface UserListResponse {
  data: AdminUser[];
  meta?: { total: number };
}

export default function UsersPage() {
  const router = useRouter();
  const [role, setRole] = useState('');
  const [blocked, setBlocked] = useState('');
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(1);

  const [busyId, setBusyId] = useState<string | null>(null);
  const [blockTarget, setBlockTarget] = useState<AdminUser | null>(null);
  const [reason, setReason] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const swrKey = useMemo(() => {
    const p = new URLSearchParams();
    p.set('page', String(page));
    p.set('limit', String(PAGE_SIZE));
    if (role) p.set('role', role);
    if (blocked) p.set('blocked', blocked);
    if (query) p.set('q', query);
    return `/users?${p.toString()}`;
  }, [role, blocked, query, page]);

  const { data, isLoading, error, mutate } = useSWR<UserListResponse>(
    swrKey,
    (path: string) =>
      apiFetchList<AdminUser[]>(path).then((r) => ({ data: r.data ?? [], meta: r.meta })),
    { revalidateOnFocus: false, keepPreviousData: true },
  );

  const rows = data?.data ?? [];
  const total = data?.meta?.total ?? rows.length;

  function submitSearch(e: React.FormEvent) {
    e.preventDefault();
    setPage(1);
    setQuery(search.trim());
  }

  async function runUnblock(user: AdminUser) {
    setBusyId(user.id);
    setActionError(null);
    try {
      await apiFetch(`/users/${user.id}/unblock`, { method: 'POST' });
      await mutate();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Failed to unblock user.');
    } finally {
      setBusyId(null);
    }
  }

  function openBlock(user: AdminUser) {
    setBlockTarget(user);
    setReason('');
    setActionError(null);
  }

  async function confirmBlock() {
    if (!blockTarget) return;
    const trimmed = reason.trim();
    if (!trimmed) {
      setActionError('A reason is required.');
      return;
    }
    setSubmitting(true);
    setActionError(null);
    try {
      await apiFetch(`/users/${blockTarget.id}/block`, {
        method: 'POST',
        body: { reason: trimmed },
      });
      setBlockTarget(null);
      await mutate();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Failed to block user.');
    } finally {
      setSubmitting(false);
    }
  }

  const columns: Column<AdminUser>[] = [
    {
      key: 'user',
      header: 'User',
      render: (u) => <UserCell user={u} />,
    },
    {
      key: 'role',
      header: 'Role',
      align: 'center',
      render: (u) => (
        <Badge tone={ROLE_TONE[u.role] ?? 'gray'}>
          {u.role.charAt(0) + u.role.slice(1).toLowerCase()}
        </Badge>
      ),
    },
    {
      key: 'city',
      header: 'City',
      hideOnMobile: true,
      accessor: (u) => <span className="text-slate-600">{u.city || '—'}</span>,
    },
    {
      key: 'bookings',
      header: 'Bookings',
      align: 'center',
      hideOnMobile: true,
      accessor: (u) => u.counts?.bookingsAsCustomer ?? 0,
    },
    {
      key: 'joined',
      header: 'Joined',
      hideOnMobile: true,
      accessor: (u) => <span className="text-slate-500">{formatDate(u.createdAt)}</span>,
    },
    {
      key: 'status',
      header: 'Status',
      align: 'center',
      render: (u) =>
        u.isBlocked ? (
          <Badge tone="red" dot>
            Blocked
          </Badge>
        ) : (
          <Badge tone="green" dot>
            Active
          </Badge>
        ),
    },
    {
      key: 'actions',
      header: 'Actions',
      align: 'right',
      render: (u) => {
        const stop = (fn: () => void) => (e: React.MouseEvent) => {
          e.stopPropagation();
          fn();
        };
        if (u.role === 'ADMIN') {
          return <span className="text-xs text-slate-400">—</span>;
        }
        return u.isBlocked ? (
          <Button
            size="sm"
            variant="success"
            loading={busyId === u.id}
            onClick={stop(() => runUnblock(u))}
            leftIcon={<CheckCircle2 className="h-3.5 w-3.5" />}
          >
            Unblock
          </Button>
        ) : (
          <Button
            size="sm"
            variant="outline"
            onClick={stop(() => openBlock(u))}
            leftIcon={<Ban className="h-3.5 w-3.5" />}
          >
            Block
          </Button>
        );
      },
    },
  ];

  return (
    <div>
      <PageHeader
        eyebrow="Accounts"
        title="Users"
        description="Search and moderate every customer and companion account on the platform."
      />

      {/* Filters */}
      <Card className="mb-4">
        <form
          onSubmit={submitSearch}
          className="flex flex-col gap-3 sm:flex-row sm:items-end"
        >
          <Input
            label="Search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Name, mobile, email or referral code…"
            leftIcon={<Search className="h-4 w-4" />}
            containerClassName="flex-1"
          />
          <Select
            label="Role"
            value={role}
            onChange={(e) => {
              setRole(e.target.value);
              setPage(1);
            }}
            options={ROLE_OPTIONS}
            containerClassName="w-full sm:w-44"
          />
          <Select
            label="Status"
            value={blocked}
            onChange={(e) => {
              setBlocked(e.target.value);
              setPage(1);
            }}
            options={BLOCKED_OPTIONS}
            containerClassName="w-full sm:w-44"
          />
          <Button type="submit" className="sm:w-auto">
            Search
          </Button>
        </form>
      </Card>

      {actionError && !blockTarget && (
        <Card className="mb-4 border-2 border-ink bg-rose-50">
          <p className="text-sm text-rose-700">{actionError}</p>
        </Card>
      )}

      {error ? (
        <Card className="border-2 border-ink bg-rose-50">
          <p className="text-sm text-rose-700">
            Couldn’t load users. {(error as Error)?.message}
          </p>
        </Card>
      ) : (
        <DataTable
          columns={columns}
          rows={rows}
          rowKey={(u) => u.id}
          loading={isLoading}
          emptyMessage="No users match these filters."
          onRowClick={(u) => router.push(`/users/${u.id}`)}
          pagination={{ page, limit: PAGE_SIZE, total, onPageChange: setPage }}
        />
      )}

      {/* Block modal */}
      <Modal
        open={Boolean(blockTarget)}
        onClose={() => (submitting ? null : setBlockTarget(null))}
        dismissible={!submitting}
        title="Block user"
        description={
          blockTarget
            ? `${blockTarget.fullName} will lose access. If they are a companion, their listing is suspended too.`
            : undefined
        }
        footer={
          <>
            <Button variant="ghost" onClick={() => setBlockTarget(null)} disabled={submitting}>
              Cancel
            </Button>
            <Button variant="danger" loading={submitting} onClick={confirmBlock}>
              Block user
            </Button>
          </>
        }
      >
        <div className="mb-3 flex items-start gap-2.5 rounded-md border-2 border-ink bg-rose-50 px-3 py-2.5">
          <ShieldOff className="mt-0.5 h-4 w-4 shrink-0 text-rose-500" />
          <p className="text-xs text-rose-700">
            Blocked users cannot log in, book, or message. They are notified of the reason.
          </p>
        </div>
        <label className="mb-1.5 block text-sm font-medium text-slate-700">Reason</label>
        <textarea
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          rows={3}
          autoFocus
          placeholder="e.g. Repeated harassment reports confirmed."
          className="w-full rounded-md border-2 border-ink bg-white p-3 text-sm text-slate-900 transition-colors focus:border-brand-500 focus:ring-2 focus:ring-brand-500/40"
        />
        {actionError && blockTarget && <p className="mt-2 text-xs text-rose-600">{actionError}</p>}
      </Modal>
    </div>
  );
}

function UserCell({ user }: { user: AdminUser }) {
  const initial = (user.fullName || '?').charAt(0).toUpperCase();
  return (
    <div className="flex items-center gap-3">
      {user.profilePhotoUrl ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={user.profilePhotoUrl}
          alt={user.fullName}
          className="h-10 w-10 shrink-0 rounded-full border-2 border-ink object-cover"
        />
      ) : (
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full border-2 border-ink bg-brand-50 text-sm font-bold text-brand-700">
          {initial}
        </span>
      )}
      <div className="min-w-0">
        <p className="truncate font-medium text-slate-900">{user.fullName}</p>
        <p className="truncate text-xs text-slate-500">
          {user.username ? `@${user.username} · ` : ''}
          {user.mobileNumber}
          {user.email ? ` · ${user.email}` : ''}
        </p>
      </div>
    </div>
  );
}

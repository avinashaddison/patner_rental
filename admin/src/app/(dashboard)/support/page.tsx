'use client';

/**
 * Admin → Support
 *
 * Support desk for user-raised tickets. Filter by status and priority, open a ticket to
 * read the full conversation thread, reply to the user, and move the ticket through its
 * lifecycle (Open → In progress → Resolved → Closed).
 *
 * Backed by (docs/API.md → ADMIN API):
 *   GET  /admin/support/tickets?status=&page=&limit=
 *   GET  /admin/support/tickets/:id                  (detail incl. messages)
 *   POST /admin/support/tickets/:id/reply   { message }
 *   POST /admin/support/tickets/:id/status  { status }
 */

import { useMemo, useState } from 'react';
import useSWR from 'swr';
import {
  CheckCircle2,
  Headset,
  LifeBuoy,
  MessageSquare,
  Send,
  ShieldCheck,
} from 'lucide-react';
import { PageHeader } from '@/components/ui/PageHeader';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { Select } from '@/components/ui/Select';
import { Badge, StatusBadge } from '@/components/ui/Badge';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { LoadingState } from '@/components/ui/Spinner';
import { apiFetch, apiFetchList, swrFetcher, ApiError } from '@/lib/api';
import { formatDateTime, timeAgo } from '@/lib/format';
import type {
  AdminSupportTicket,
  AdminTicketMessage,
  TicketPriority,
  TicketStatus,
} from '@/lib/types';

const PAGE_SIZE = 20;

const STATUS_FILTER: { label: string; value: '' | TicketStatus }[] = [
  { label: 'All statuses', value: '' },
  { label: 'Open', value: 'OPEN' },
  { label: 'In progress', value: 'IN_PROGRESS' },
  { label: 'Resolved', value: 'RESOLVED' },
  { label: 'Closed', value: 'CLOSED' },
];

const PRIORITY_FILTER: { label: string; value: '' | TicketPriority }[] = [
  { label: 'All priorities', value: '' },
  { label: 'Urgent', value: 'URGENT' },
  { label: 'High', value: 'HIGH' },
  { label: 'Medium', value: 'MEDIUM' },
  { label: 'Low', value: 'LOW' },
];

// Statuses an admin can move a ticket into (used in the detail modal).
const STATUS_CHANGE: { label: string; value: TicketStatus }[] = [
  { label: 'Open', value: 'OPEN' },
  { label: 'In progress', value: 'IN_PROGRESS' },
  { label: 'Resolved', value: 'RESOLVED' },
  { label: 'Closed', value: 'CLOSED' },
];

interface TicketListResponse {
  data: AdminSupportTicket[];
  meta?: { total: number };
}

export default function SupportPage() {
  const [status, setStatus] = useState<'' | TicketStatus>('');
  const [priority, setPriority] = useState<'' | TicketPriority>('');
  const [page, setPage] = useState(1);
  const [activeId, setActiveId] = useState<string | null>(null);

  const swrKey = useMemo(() => {
    const p = new URLSearchParams();
    p.set('page', String(page));
    p.set('limit', String(PAGE_SIZE));
    if (status) p.set('status', status);
    return `/support/tickets?${p.toString()}`;
  }, [status, page]);

  // Auto-refresh every 5s so user messages land in the desk live.
  const { data, isLoading, error, mutate } = useSWR<TicketListResponse>(
    swrKey,
    (path: string) =>
      apiFetchList<AdminSupportTicket[]>(path).then((r) => ({
        data: r.data ?? [],
        meta: r.meta,
      })),
    { revalidateOnFocus: true, keepPreviousData: true, refreshInterval: 5000 },
  );

  // Live count of threads awaiting an admin reply (drives the live badge).
  const { data: unread } = useSWR<{ count: number }>(
    '/support/unread-count',
    swrFetcher,
    { refreshInterval: 5000, revalidateOnFocus: true },
  );
  const awaiting = unread?.count ?? 0;

  // Priority is filtered client-side (the admin list endpoint keys on status).
  const allRows = data?.data ?? [];
  const rows = priority ? allRows.filter((t) => t.priority === priority) : allRows;
  const total = data?.meta?.total ?? allRows.length;

  const columns: Column<AdminSupportTicket>[] = [
    {
      key: 'subject',
      header: 'Ticket',
      render: (t) => (
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <p className="truncate font-bold text-ink">{t.subject}</p>
            {t.awaitingReply && (
              <span className="shrink-0 rounded-full border-2 border-ink bg-lime-400 px-2 py-0.5 text-[10px] font-bold text-ink">
                ● Awaiting reply
              </span>
            )}
          </div>
          <p className="truncate text-xs text-slate-500">
            {t.user?.fullName ?? 'Unknown user'}
            {t.user?.mobileNumber ? ` · ${t.user.mobileNumber}` : ''}
          </p>
        </div>
      ),
    },
    {
      key: 'priority',
      header: 'Priority',
      align: 'center',
      render: (t) => <StatusBadge status={t.priority} />,
    },
    {
      key: 'created',
      header: 'Opened',
      hideOnMobile: true,
      accessor: (t) => <span className="text-slate-500">{timeAgo(t.createdAt)}</span>,
    },
    {
      key: 'status',
      header: 'Status',
      align: 'center',
      render: (t) => <StatusBadge status={t.status} />,
    },
    {
      key: 'actions',
      header: 'Actions',
      align: 'right',
      render: (t) => (
        <Button
          size="sm"
          variant="outline"
          leftIcon={<MessageSquare className="h-3.5 w-3.5" />}
          onClick={(e) => {
            e.stopPropagation();
            setActiveId(t.id);
          }}
        >
          Open
        </Button>
      ),
    },
  ];

  return (
    <div>
      <PageHeader
        eyebrow="Support desk"
        title="Support"
        description="Respond to user tickets and keep the queue moving. Reply, then update the ticket status."
      />

      {/* Live inbox indicator — refreshes every 5s. */}
      <div className="mb-4 flex items-center gap-2">
        <span className="relative flex h-2.5 w-2.5">
          <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-75" />
          <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-emerald-500" />
        </span>
        <span className="text-sm font-bold text-slate-600">
          Live inbox
          {awaiting > 0 ? (
            <>
              {' — '}
              <span className="font-extrabold text-emerald-700">
                {awaiting} awaiting reply
              </span>
            </>
          ) : (
            ' — all caught up'
          )}
        </span>
      </div>

      <Card className="mb-4">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
          <Select
            label="Status"
            value={status}
            onChange={(e) => {
              setStatus(e.target.value as '' | TicketStatus);
              setPage(1);
            }}
            options={STATUS_FILTER}
            containerClassName="w-full sm:w-48"
          />
          <Select
            label="Priority"
            value={priority}
            onChange={(e) => {
              setPriority(e.target.value as '' | TicketPriority);
              setPage(1);
            }}
            options={PRIORITY_FILTER}
            containerClassName="w-full sm:w-48"
          />
          <div className="flex items-center gap-2 sm:ml-auto sm:pb-0.5">
            <Headset className="h-4 w-4 text-brand-500" />
            <span className="text-xs text-slate-500">
              Reply promptly — urgent tickets first.
            </span>
          </div>
        </div>
      </Card>

      {error ? (
        <Card className="border-2 border-ink bg-red-500/10">
          <p className="text-sm font-bold text-rose-700">
            Couldn&rsquo;t load tickets. {(error as Error)?.message}
          </p>
        </Card>
      ) : (
        <DataTable
          columns={columns}
          rows={rows}
          rowKey={(t) => t.id}
          loading={isLoading}
          emptyMessage="No tickets match these filters."
          emptyIcon={<LifeBuoy className="h-8 w-8" />}
          onRowClick={(t) => setActiveId(t.id)}
          pagination={{ page, limit: PAGE_SIZE, total, onPageChange: setPage }}
        />
      )}

      <TicketModal
        ticketId={activeId}
        onClose={() => setActiveId(null)}
        onChanged={() => mutate()}
      />
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Ticket detail modal: thread + reply + status change                         */
/* -------------------------------------------------------------------------- */

function TicketModal({
  ticketId,
  onClose,
  onChanged,
}: {
  ticketId: string | null;
  onClose: () => void;
  onChanged: () => void;
}) {
  // Poll the open thread every 4s so the admin sees new user messages live.
  const { data: ticket, isLoading, mutate } = useSWR<AdminSupportTicket>(
    ticketId ? `/support/tickets/${ticketId}` : null,
    swrFetcher,
    { revalidateOnFocus: true, refreshInterval: 4000 },
  );

  const [reply, setReply] = useState('');
  const [sending, setSending] = useState(false);
  const [statusBusy, setStatusBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function sendReply() {
    if (!ticketId) return;
    const trimmed = reply.trim();
    if (!trimmed) {
      setErr('Write a message before sending.');
      return;
    }
    setSending(true);
    setErr(null);
    try {
      await apiFetch(`/support/tickets/${ticketId}/reply`, {
        method: 'POST',
        body: { message: trimmed },
      });
      setReply('');
      await mutate();
      onChanged();
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : 'Failed to send reply.');
    } finally {
      setSending(false);
    }
  }

  async function changeStatus(next: TicketStatus) {
    if (!ticketId || !ticket || next === ticket.status) return;
    setStatusBusy(true);
    setErr(null);
    try {
      await apiFetch(`/support/tickets/${ticketId}/status`, {
        method: 'POST',
        body: { status: next },
      });
      await mutate();
      onChanged();
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : 'Failed to update status.');
    } finally {
      setStatusBusy(false);
    }
  }

  // Build the thread: the original description as the first (user) message, then replies.
  const thread = ticket ? buildThread(ticket) : [];
  const canReply = ticket ? ticket.status !== 'CLOSED' : false;

  return (
    <Modal
      open={Boolean(ticketId)}
      onClose={() => (sending ? null : onClose())}
      dismissible={!sending}
      size="xl"
      title={ticket?.subject ?? 'Support ticket'}
      description={
        ticket
          ? `${ticket.user?.fullName ?? 'User'} · opened ${formatDateTime(ticket.createdAt)}`
          : undefined
      }
      footer={
        <Button variant="ghost" onClick={onClose} disabled={sending}>
          Close
        </Button>
      }
    >
      {isLoading || !ticket ? (
        <LoadingState label="Loading ticket…" />
      ) : (
        <div className="space-y-4">
          {/* Status row */}
          <div className="flex flex-wrap items-center gap-3 rounded-md border-2 border-ink bg-white px-3 py-2.5">
            <StatusBadge status={ticket.priority} />
            <StatusBadge status={ticket.status} />
            <div className="ml-auto flex items-center gap-2">
              <span className="text-xs font-bold uppercase text-slate-500">Set status</span>
              <Select
                aria-label="Change status"
                value={ticket.status}
                disabled={statusBusy}
                onChange={(e) => changeStatus(e.target.value as TicketStatus)}
                options={STATUS_CHANGE}
                className="h-9 w-40"
              />
            </div>
          </div>

          {/* Conversation thread */}
          <div className="max-h-[42vh] space-y-3 overflow-y-auto pr-1">
            {thread.map((m) => (
              <MessageBubble key={m.id} message={m} ticket={ticket} />
            ))}
          </div>

          {/* Reply box */}
          {canReply ? (
            <div>
              <label className="mb-1.5 block text-sm font-bold text-slate-700">
                Reply to {ticket.user?.fullName ?? 'user'}
              </label>
              <textarea
                value={reply}
                onChange={(e) => setReply(e.target.value)}
                rows={3}
                placeholder="Type your response…"
                className="w-full rounded-md border-2 border-ink bg-white p-3 text-sm text-slate-900 transition-colors focus:ring-2 focus:ring-brand-500/50"
              />
              <div className="mt-2 flex items-center justify-between gap-2">
                <p className="text-xs text-slate-400">
                  The user is notified of your reply.
                </p>
                <div className="flex items-center gap-2">
                  {ticket.status !== 'RESOLVED' && (
                    <Button
                      variant="success"
                      size="sm"
                      loading={statusBusy}
                      onClick={() => changeStatus('RESOLVED')}
                      leftIcon={<CheckCircle2 className="h-3.5 w-3.5" />}
                    >
                      Mark resolved
                    </Button>
                  )}
                  <Button
                    size="sm"
                    loading={sending}
                    onClick={sendReply}
                    leftIcon={<Send className="h-3.5 w-3.5" />}
                  >
                    Send reply
                  </Button>
                </div>
              </div>
            </div>
          ) : (
            <div className="flex items-center gap-2 rounded-md border-2 border-ink bg-slate-50 px-3 py-2.5 text-sm text-slate-500">
              <ShieldCheck className="h-4 w-4 text-brand-500" />
              This ticket is closed. Re-open it to reply.
            </div>
          )}

          {err && <p className="text-xs text-rose-600">{err}</p>}
        </div>
      )}
    </Modal>
  );
}

/** Synthesize an ordered thread from the ticket description + reply messages. */
function buildThread(ticket: AdminSupportTicket): AdminTicketMessage[] {
  const sorted = (ticket.messages ?? [])
    .slice()
    .sort((a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime());
  // Live Support Chat threads are pure message lists — the description is a
  // placeholder, so don't prepend a synthetic opener (it'd duplicate message #1).
  if (ticket.subject === 'Live Support Chat') return sorted;
  const opener: AdminTicketMessage = {
    id: `__opener_${ticket.id}`,
    ticketId: ticket.id,
    senderId: ticket.userId,
    message: ticket.description,
    createdAt: ticket.createdAt,
    sender: ticket.user
      ? { id: ticket.user.id, fullName: ticket.user.fullName, role: ticket.user.role }
      : undefined,
  };
  const replies = (ticket.messages ?? [])
    .slice()
    .sort((a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime());
  // Avoid duplicating the opener if the backend already includes it as message #1.
  const deduped = replies.filter((m) => m.message !== ticket.description || m.id !== opener.id);
  return [opener, ...deduped];
}

function MessageBubble({
  message,
  ticket,
}: {
  message: AdminTicketMessage;
  ticket: AdminSupportTicket;
}) {
  const fromUser = message.senderId === ticket.userId;
  const name = fromUser
    ? ticket.user?.fullName ?? 'User'
    : message.sender?.fullName ?? 'Support';
  return (
    <div className={fromUser ? 'flex justify-start' : 'flex justify-end'}>
      <div
        className={
          'max-w-[80%] rounded-md border-2 border-ink px-3.5 py-2.5 shadow-brutal-xs ' +
          (fromUser
            ? 'bg-white text-slate-800'
            : 'bg-brand-500 text-white')
        }
      >
        <div className="mb-0.5 flex items-center gap-2">
          <span className={'text-xs font-semibold ' + (fromUser ? 'text-slate-600' : 'text-white/90')}>
            {name}
          </span>
          {!fromUser && (
            <Badge tone="purple" className="border-2 border-ink bg-acid text-ink">
              Admin
            </Badge>
          )}
        </div>
        <p className="whitespace-pre-wrap text-sm leading-relaxed">{message.message}</p>
        <p className={'mt-1 text-[11px] ' + (fromUser ? 'text-slate-400' : 'text-white/70')}>
          {formatDateTime(message.createdAt)}
        </p>
      </div>
    </div>
  );
}

import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';

export type BadgeTone =
  | 'gray'
  | 'brand'
  | 'green'
  | 'amber'
  | 'red'
  | 'blue'
  | 'purple';

export interface BadgeProps {
  children: ReactNode;
  tone?: BadgeTone;
  /** Show a leading status dot. */
  dot?: boolean;
  className?: string;
}

const tones: Record<BadgeTone, { wrap: string; dot: string }> = {
  gray: { wrap: 'bg-slate-200 text-ink', dot: 'bg-ink' },
  brand: { wrap: 'bg-brand-500 text-white', dot: 'bg-white' },
  green: { wrap: 'bg-lime-400 text-ink', dot: 'bg-ink' },
  amber: { wrap: 'bg-acid text-ink', dot: 'bg-ink' },
  red: { wrap: 'bg-red-500 text-white', dot: 'bg-white' },
  blue: { wrap: 'bg-sky-400 text-ink', dot: 'bg-ink' },
  purple: { wrap: 'bg-violet-400 text-ink', dot: 'bg-ink' },
};

/**
 * Maps the domain status enums (DATA_MODEL.md) to badge tones so every page renders
 * statuses consistently. Unknown values fall back to gray.
 */
const STATUS_TONE: Record<string, BadgeTone> = {
  // BookingStatus
  PENDING: 'amber',
  CONFIRMED: 'blue',
  IN_PROGRESS: 'purple',
  COMPLETED: 'green',
  CANCELLED: 'red',
  REFUNDED: 'gray',
  // PaymentStatus
  CREATED: 'gray',
  AUTHORIZED: 'blue',
  CAPTURED: 'green',
  FAILED: 'red',
  // KycStatus / CompanionStatus
  SUBMITTED: 'blue',
  APPROVED: 'green',
  REJECTED: 'red',
  SUSPENDED: 'red',
  // PayoutStatus
  REQUESTED: 'amber',
  PROCESSING: 'blue',
  // ReportStatus
  OPEN: 'amber',
  REVIEWING: 'blue',
  RESOLVED: 'green',
  DISMISSED: 'gray',
  // TicketStatus
  CLOSED: 'gray',
  // TicketPriority
  LOW: 'gray',
  MEDIUM: 'blue',
  HIGH: 'amber',
  URGENT: 'red',
  // SosStatus
  ACTIVE: 'red',
};

export function Badge({ children, tone = 'gray', dot = false, className }: BadgeProps) {
  const t = tones[tone];
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 whitespace-nowrap rounded border-2 border-ink px-2 py-0.5 text-xs font-bold shadow-brutal-xs',
        t.wrap,
        className,
      )}
    >
      {dot && <span className={cn('h-1.5 w-1.5 rounded-full', t.dot)} />}
      {children}
    </span>
  );
}

/** Convenience badge that derives tone + humanized label from a status enum value. */
export function StatusBadge({ status, className }: { status: string; className?: string }) {
  const tone = STATUS_TONE[status] ?? 'gray';
  const label = status
    .replace(/_/g, ' ')
    .toLowerCase()
    .replace(/\b\w/g, (c) => c.toUpperCase());
  return (
    <Badge tone={tone} dot className={className}>
      {label}
    </Badge>
  );
}

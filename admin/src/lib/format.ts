/**
 * Shared formatting helpers for the admin panel.
 * Money is always INR (see DATA_MODEL.md — all amounts Decimal(10,2) INR).
 */

const INR = new Intl.NumberFormat('en-IN', {
  style: 'currency',
  currency: 'INR',
  maximumFractionDigits: 2,
});

const INR_COMPACT = new Intl.NumberFormat('en-IN', {
  style: 'currency',
  currency: 'INR',
  notation: 'compact',
  maximumFractionDigits: 1,
});

/** Format an INR amount. Backend may send Decimal as string or number. */
export function formatINR(value: number | string | null | undefined): string {
  if (value === null || value === undefined || value === '') return '₹0';
  const n = typeof value === 'string' ? Number(value) : value;
  if (Number.isNaN(n)) return '₹0';
  return INR.format(n);
}

/** Compact INR for KPI cards (e.g. ₹1.2L). */
export function formatINRCompact(value: number | string | null | undefined): string {
  if (value === null || value === undefined || value === '') return '₹0';
  const n = typeof value === 'string' ? Number(value) : value;
  if (Number.isNaN(n)) return '₹0';
  return INR_COMPACT.format(n);
}

/** Plain integer with Indian grouping. */
export function formatNumber(value: number | string | null | undefined): string {
  if (value === null || value === undefined || value === '') return '0';
  const n = typeof value === 'string' ? Number(value) : value;
  if (Number.isNaN(n)) return '0';
  return new Intl.NumberFormat('en-IN').format(n);
}

/** ISO timestamp → "27 Jun 2026, 11:42 PM" (IST-friendly readable). */
export function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleString('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

/** ISO date → "27 Jun 2026". */
export function formatDate(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleDateString('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  });
}

/** Relative "time ago" for activity feeds. */
export function timeAgo(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso).getTime();
  if (Number.isNaN(d)) return '—';
  const diff = Date.now() - d;
  const sec = Math.round(diff / 1000);
  if (sec < 60) return 'just now';
  const min = Math.round(sec / 60);
  if (min < 60) return `${min}m ago`;
  const hr = Math.round(min / 60);
  if (hr < 24) return `${hr}h ago`;
  const day = Math.round(hr / 24);
  if (day < 30) return `${day}d ago`;
  return formatDate(iso);
}

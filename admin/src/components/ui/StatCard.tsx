import type { ReactNode } from 'react';
import { ArrowDownRight, ArrowUpRight } from 'lucide-react';
import { cn } from '@/lib/cn';

export interface StatCardProps {
  label: string;
  value: ReactNode;
  icon?: ReactNode;
  /** Signed percentage delta vs. previous period (e.g. 12.4 or -3.1). */
  delta?: number;
  deltaLabel?: string;
  /** Accent color for the icon chip. */
  tone?: 'brand' | 'emerald' | 'amber' | 'sky' | 'rose';
  loading?: boolean;
}

const tones: Record<NonNullable<StatCardProps['tone']>, string> = {
  brand: 'border-2 border-ink bg-brand-500 text-white',
  emerald: 'border-2 border-ink bg-lime-400 text-ink',
  amber: 'border-2 border-ink bg-acid text-ink',
  sky: 'border-2 border-ink bg-sky-400 text-ink',
  rose: 'border-2 border-ink bg-red-500 text-white',
};

export function StatCard({
  label,
  value,
  icon,
  delta,
  deltaLabel = 'vs last period',
  tone = 'brand',
  loading = false,
}: StatCardProps) {
  const hasDelta = typeof delta === 'number' && Number.isFinite(delta);
  const positive = hasDelta && delta! >= 0;

  return (
    <div className="group rounded-md border-2 border-ink bg-white p-5 shadow-brutal transition-all duration-100 hover:-translate-x-0.5 hover:-translate-y-0.5 hover:shadow-brutal-md">
      <div className="flex items-start justify-between">
        <span className="text-xs font-bold uppercase tracking-wide text-slate-500">{label}</span>
        {icon && (
          <span
            className={cn(
              'flex h-11 w-11 items-center justify-center rounded-md',
              tones[tone],
            )}
          >
            {icon}
          </span>
        )}
      </div>

      {loading ? (
        <div className="mt-3 h-9 w-28 animate-pulse rounded-md border-2 border-ink bg-slate-100" />
      ) : (
        <div className="mt-3 text-3xl font-black tracking-tight text-ink">{value}</div>
      )}

      {hasDelta && !loading && (
        <div className="mt-2 flex items-center gap-1 text-xs">
          <span
            className={cn(
              'inline-flex items-center gap-0.5 rounded border-2 border-ink px-1.5 py-0.5 font-bold',
              positive ? 'bg-lime-400 text-ink' : 'bg-red-500 text-white',
            )}
          >
            {positive ? (
              <ArrowUpRight className="h-3 w-3" />
            ) : (
              <ArrowDownRight className="h-3 w-3" />
            )}
            {Math.abs(delta!).toFixed(1)}%
          </span>
          <span className="text-slate-400">{deltaLabel}</span>
        </div>
      )}
    </div>
  );
}

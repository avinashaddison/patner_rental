import { Loader2 } from 'lucide-react';
import { cn } from '@/lib/cn';

export interface SpinnerProps {
  size?: 'sm' | 'md' | 'lg';
  className?: string;
  label?: string;
}

const sizes = {
  sm: 'h-4 w-4',
  md: 'h-6 w-6',
  lg: 'h-8 w-8',
};

export function Spinner({ size = 'md', className, label }: SpinnerProps) {
  return (
    <span className="inline-flex items-center gap-2 text-slate-500" role="status">
      <Loader2 className={cn('animate-spin text-brand-600', sizes[size], className)} aria-hidden />
      {label && <span className="text-sm">{label}</span>}
      <span className="sr-only">{label ?? 'Loading'}</span>
    </span>
  );
}

/** Centered full-area spinner for page/section loading states. */
export function LoadingState({ label = 'Loading…' }: { label?: string }) {
  return (
    <div className="flex min-h-[240px] w-full items-center justify-center">
      <Spinner size="lg" label={label} />
    </div>
  );
}

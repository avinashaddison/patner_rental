import type { HTMLAttributes, ReactNode } from 'react';
import { cn } from '@/lib/cn';

export interface CardProps extends HTMLAttributes<HTMLDivElement> {
  children: ReactNode;
  /** Remove inner padding (e.g. when wrapping a table). */
  flush?: boolean;
}

export function Card({ children, className, flush = false, ...rest }: CardProps) {
  return (
    <div
      className={cn(
        'rounded-md border-2 border-ink bg-white shadow-brutal',
        !flush && 'p-5',
        className,
      )}
      {...rest}
    >
      {children}
    </div>
  );
}

export function CardHeader({
  title,
  subtitle,
  action,
  className,
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  action?: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn('mb-4 flex items-start justify-between gap-4', className)}>
      <div className="min-w-0">
        <h3 className="text-[15px] font-extrabold text-ink">{title}</h3>
        {subtitle && <p className="mt-0.5 text-sm font-medium text-slate-500">{subtitle}</p>}
      </div>
      {action && <div className="shrink-0">{action}</div>}
    </div>
  );
}

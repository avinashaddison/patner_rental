import type { ReactNode } from 'react';
import { cn } from '@/lib/cn';

export interface PageHeaderProps {
  title: string;
  description?: string;
  /** Right-aligned actions (buttons, filters). */
  actions?: ReactNode;
  /** Optional breadcrumb/eyebrow above the title. */
  eyebrow?: string;
  className?: string;
}

export function PageHeader({ title, description, actions, eyebrow, className }: PageHeaderProps) {
  return (
    <div
      className={cn(
        'mb-6 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between',
        className,
      )}
    >
      <div className="min-w-0">
        {eyebrow && (
          <span className="mb-2 inline-flex items-center rounded border-2 border-ink bg-acid px-2.5 py-0.5 text-[11px] font-bold uppercase tracking-wider text-ink shadow-brutal-xs">
            {eyebrow}
          </span>
        )}
        <h1 className="text-3xl font-black uppercase tracking-tight text-ink sm:text-4xl">{title}</h1>
        {description && <p className="mt-1.5 max-w-2xl text-sm font-medium text-slate-600">{description}</p>}
      </div>
      {actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
    </div>
  );
}

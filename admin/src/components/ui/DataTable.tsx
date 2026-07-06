'use client';

import type { ReactNode } from 'react';
import { ChevronLeft, ChevronRight, Inbox } from 'lucide-react';
import { cn } from '@/lib/cn';
import { Spinner } from './Spinner';

export interface Column<T> {
  /** Stable key; also used as React key for cells. */
  key: string;
  header: ReactNode;
  /** Render a cell. Receives the row and its index. */
  render?: (row: T, index: number) => ReactNode;
  /** Shorthand accessor when no custom render is needed. */
  accessor?: (row: T) => ReactNode;
  align?: 'left' | 'center' | 'right';
  className?: string;
  headerClassName?: string;
  /** Hide on small screens. */
  hideOnMobile?: boolean;
}

export interface DataTablePagination {
  page: number;
  limit: number;
  total: number;
  onPageChange: (page: number) => void;
}

export interface DataTableProps<T> {
  columns: Column<T>[];
  rows: T[];
  /** Unique key per row. */
  rowKey: (row: T, index: number) => string;
  loading?: boolean;
  emptyMessage?: string;
  emptyIcon?: ReactNode;
  onRowClick?: (row: T) => void;
  pagination?: DataTablePagination;
  className?: string;
}

const alignClass: Record<NonNullable<Column<unknown>['align']>, string> = {
  left: 'text-left',
  center: 'text-center',
  right: 'text-right',
};

export function DataTable<T>({
  columns,
  rows,
  rowKey,
  loading = false,
  emptyMessage = 'No records found.',
  emptyIcon,
  onRowClick,
  pagination,
  className,
}: DataTableProps<T>) {
  const colSpan = columns.length;

  const totalPages = pagination
    ? Math.max(1, Math.ceil(pagination.total / Math.max(1, pagination.limit)))
    : 1;
  const from = pagination ? (pagination.page - 1) * pagination.limit + 1 : 0;
  const to = pagination ? Math.min(pagination.page * pagination.limit, pagination.total) : 0;

  return (
    <div
      className={cn(
        'overflow-hidden rounded-md border-2 border-ink bg-white shadow-brutal',
        className,
      )}
    >
      <div className="scrollbar-thin overflow-x-auto">
        <table className="w-full border-collapse text-sm">
          <thead>
            <tr className="border-b-2 border-ink bg-ink">
              {columns.map((col) => (
                <th
                  key={col.key}
                  scope="col"
                  className={cn(
                    'px-4 py-3 text-xs font-bold uppercase tracking-wide text-white',
                    alignClass[col.align ?? 'left'],
                    col.hideOnMobile && 'hidden md:table-cell',
                    col.headerClassName,
                  )}
                >
                  {col.header}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y-2 divide-slate-100">
            {loading ? (
              <tr>
                <td colSpan={colSpan} className="px-4 py-16">
                  <div className="flex justify-center">
                    <Spinner size="lg" label="Loading…" />
                  </div>
                </td>
              </tr>
            ) : rows.length === 0 ? (
              <tr>
                <td colSpan={colSpan} className="px-4 py-16">
                  <div className="flex flex-col items-center justify-center gap-2 text-slate-400">
                    {emptyIcon ?? <Inbox className="h-8 w-8" />}
                    <p className="text-sm">{emptyMessage}</p>
                  </div>
                </td>
              </tr>
            ) : (
              rows.map((row, index) => (
                <tr
                  key={rowKey(row, index)}
                  onClick={onRowClick ? () => onRowClick(row) : undefined}
                  className={cn(
                    'transition-colors',
                    onRowClick && 'cursor-pointer hover:bg-acid/30',
                  )}
                >
                  {columns.map((col) => (
                    <td
                      key={col.key}
                      className={cn(
                        'px-4 py-3 font-medium text-slate-700',
                        alignClass[col.align ?? 'left'],
                        col.hideOnMobile && 'hidden md:table-cell',
                        col.className,
                      )}
                    >
                      {col.render
                        ? col.render(row, index)
                        : col.accessor
                          ? col.accessor(row)
                          : null}
                    </td>
                  ))}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {pagination && pagination.total > 0 && (
        <div className="flex items-center justify-between gap-4 border-t-2 border-ink bg-slate-50 px-4 py-3">
          <p className="text-xs text-slate-500">
            Showing <span className="font-medium text-slate-700">{from}</span>–
            <span className="font-medium text-slate-700">{to}</span> of{' '}
            <span className="font-medium text-slate-700">{pagination.total}</span>
          </p>
          <div className="flex items-center gap-1">
            <button
              type="button"
              disabled={pagination.page <= 1}
              onClick={() => pagination.onPageChange(pagination.page - 1)}
              className="inline-flex h-8 items-center gap-1 rounded border-2 border-ink bg-white px-3 text-xs font-bold text-ink shadow-brutal-xs transition-all hover:bg-acid active:translate-x-0.5 active:translate-y-0.5 active:shadow-none disabled:cursor-not-allowed disabled:opacity-40"
            >
              <ChevronLeft className="h-4 w-4" />
              Prev
            </button>
            <span className="px-2 text-xs text-slate-500">
              Page {pagination.page} of {totalPages}
            </span>
            <button
              type="button"
              disabled={pagination.page >= totalPages}
              onClick={() => pagination.onPageChange(pagination.page + 1)}
              className="inline-flex h-8 items-center gap-1 rounded border-2 border-ink bg-white px-3 text-xs font-bold text-ink shadow-brutal-xs transition-all hover:bg-acid active:translate-x-0.5 active:translate-y-0.5 active:shadow-none disabled:cursor-not-allowed disabled:opacity-40"
            >
              Next
              <ChevronRight className="h-4 w-4" />
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

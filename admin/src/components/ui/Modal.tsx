'use client';

import { useEffect, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { X } from 'lucide-react';
import { cn } from '@/lib/cn';

export interface ModalProps {
  open: boolean;
  onClose: () => void;
  title?: ReactNode;
  description?: ReactNode;
  children?: ReactNode;
  footer?: ReactNode;
  size?: 'sm' | 'md' | 'lg' | 'xl';
  /** Disable closing via backdrop/escape (e.g. during a submit). */
  dismissible?: boolean;
}

const sizes = {
  sm: 'max-w-sm',
  md: 'max-w-md',
  lg: 'max-w-lg',
  xl: 'max-w-2xl',
};

export function Modal({
  open,
  onClose,
  title,
  description,
  children,
  footer,
  size = 'md',
  dismissible = true,
}: ModalProps) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && dismissible) onClose();
    };
    document.addEventListener('keydown', onKey);
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', onKey);
      document.body.style.overflow = prevOverflow;
    };
  }, [open, onClose, dismissible]);

  if (!open || typeof document === 'undefined') return null;

  return createPortal(
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      role="dialog"
      aria-modal="true"
      aria-label={typeof title === 'string' ? title : 'Dialog'}
    >
      <div
        className="absolute inset-0 bg-ink/40"
        onClick={() => dismissible && onClose()}
      />
      <div
        className={cn(
          'relative w-full animate-pop-in rounded-md border-2 border-ink bg-white shadow-brutal-xl',
          sizes[size],
        )}
      >
        {(title || dismissible) && (
          <div className="flex items-start justify-between gap-4 border-b-2 border-ink px-5 py-4">
            <div className="min-w-0">
              {title && <h2 className="text-lg font-extrabold text-ink">{title}</h2>}
              {description && <p className="mt-0.5 text-sm font-medium text-slate-500">{description}</p>}
            </div>
            {dismissible && (
              <button
                type="button"
                onClick={onClose}
                className="rounded border-2 border-ink bg-white p-1 text-ink shadow-brutal-xs transition-all hover:bg-acid active:translate-x-0.5 active:translate-y-0.5 active:shadow-none"
                aria-label="Close dialog"
              >
                <X className="h-5 w-5" />
              </button>
            )}
          </div>
        )}

        {children && <div className="px-6 py-4">{children}</div>}

        {footer && (
          <div className="flex items-center justify-end gap-2 border-t-2 border-ink px-5 py-4">
            {footer}
          </div>
        )}
      </div>
    </div>,
    document.body,
  );
}

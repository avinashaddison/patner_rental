import { forwardRef } from 'react';
import type { ButtonHTMLAttributes, ReactNode } from 'react';
import { Loader2 } from 'lucide-react';
import { cn } from '@/lib/cn';

export type ButtonVariant =
  | 'primary'
  | 'secondary'
  | 'outline'
  | 'ghost'
  | 'danger'
  | 'success';
export type ButtonSize = 'sm' | 'md' | 'lg' | 'icon';

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  loading?: boolean;
  leftIcon?: ReactNode;
  rightIcon?: ReactNode;
}

// Brutalist buttons: flat fill, 2px black border, hard offset shadow that
// "presses" flat on click. The press motion is shared via the base classes.
const variants: Record<ButtonVariant, string> = {
  primary: 'bg-brand-500 text-white',
  secondary: 'bg-acid text-ink',
  outline: 'bg-white text-ink',
  ghost:
    'border-transparent !shadow-none text-ink hover:border-ink hover:bg-acid hover:!shadow-brutal-sm active:translate-x-0 active:translate-y-0',
  danger: 'bg-red-500 text-white',
  success: 'bg-lime-400 text-ink',
};

const sizes: Record<ButtonSize, string> = {
  sm: 'h-8 px-3.5 text-xs gap-1.5',
  md: 'h-10 px-5 text-sm gap-2',
  lg: 'h-12 px-7 text-base gap-2.5',
  icon: 'h-10 w-10 p-0',
};

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  {
    variant = 'primary',
    size = 'md',
    loading = false,
    leftIcon,
    rightIcon,
    className,
    children,
    disabled,
    type = 'button',
    ...rest
  },
  ref,
) {
  return (
    <button
      ref={ref}
      type={type}
      disabled={disabled || loading}
      className={cn(
        'inline-flex select-none items-center justify-center rounded-md border-2 border-ink font-bold shadow-brutal transition-all duration-100',
        'hover:-translate-x-0.5 hover:-translate-y-0.5 hover:shadow-brutal-md',
        'active:translate-x-[3px] active:translate-y-[3px] active:shadow-none',
        'focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2',
        'disabled:cursor-not-allowed disabled:opacity-50 disabled:translate-x-0 disabled:translate-y-0 disabled:shadow-brutal',
        variants[variant],
        sizes[size],
        className,
      )}
      {...rest}
    >
      {loading ? (
        <Loader2 className="h-4 w-4 animate-spin" aria-hidden />
      ) : (
        leftIcon
      )}
      {children}
      {!loading && rightIcon}
    </button>
  );
});

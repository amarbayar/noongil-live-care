import { cn } from '@/lib/utils';
import { type SelectHTMLAttributes, forwardRef } from 'react';

export const Select = forwardRef<
  HTMLSelectElement,
  SelectHTMLAttributes<HTMLSelectElement>
>(({ className, ...props }, ref) => (
  <select
    ref={ref}
    className={cn(
      'h-9 w-full rounded-lg border border-input bg-background px-3 py-1 text-sm shadow-sm transition-colors focus:outline-none focus:ring-2 focus:ring-ring',
      className
    )}
    {...props}
  />
));
Select.displayName = 'Select';

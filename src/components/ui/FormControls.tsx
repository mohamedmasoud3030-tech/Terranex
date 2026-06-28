import { type InputHTMLAttributes } from 'react';
import { cn } from '../../core/lib/cn';

export const controlClassName = 'block w-full rounded-xl border border-border bg-background px-3 py-2.5 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary';

export function TextInput({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return <input className={cn(controlClassName, className)} {...props} />;
}

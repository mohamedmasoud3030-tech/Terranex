// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import AppError from '@/app/(app)/error';

describe('app-level error boundary', () => {
  afterEach(() => cleanup());

  it('shows an Arabic recoverable state with a retry action', () => {
    const reset = vi.fn();
    render(<AppError error={new Error('boom')} reset={reset} />);
    expect(screen.getByRole('alert')).toBeDefined();
    expect(screen.getByRole('heading', { name: 'حدث خطأ غير متوقع' })).toBeDefined();
    fireEvent.click(screen.getByRole('button', { name: 'إعادة المحاولة' }));
    expect(reset).toHaveBeenCalledTimes(1);
  });

  it('offers a way back to the dashboard without exposing the raw error', () => {
    render(<AppError error={new Error('secret-detail')} reset={() => {}} />);
    expect(screen.getByRole('link', { name: 'العودة إلى اللوحة الرئيسية' })).toBeDefined();
    expect(document.body.textContent).not.toContain('secret-detail');
  });
});

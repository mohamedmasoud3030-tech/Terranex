// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { OrganizationSwitcher } from '@/features/organizations/switcher';
import { ACTIVE_ORG_COOKIE } from '@/features/organizations/active-org';

const refresh = vi.fn();
vi.mock('next/navigation', () => ({
  useRouter: () => ({ refresh }),
}));

const orgs = [
  { id: '00000000-0000-4000-8000-000000000001', name: 'المنظمة الأولى' },
  { id: '00000000-0000-4000-8000-000000000002', name: 'المنظمة الثانية' },
];

describe('OrganizationSwitcher', () => {
  beforeEach(() => {
    document.cookie.split(';').forEach((part) => {
      const [name] = part.trim().split('=');
      document.cookie = `${name}=; path=/; max-age=0`;
    });
    refresh.mockClear();
  });

  afterEach(() => cleanup());

  it('renders nothing for a single organization', () => {
    const { container } = render(
      <OrganizationSwitcher organizations={orgs.slice(0, 1)} activeId={orgs[0].id} />,
    );
    expect(container.querySelector('select')).toBeNull();
  });

  it('renders a labelled select with every membership organization', () => {
    render(<OrganizationSwitcher organizations={orgs} activeId={orgs[0].id} />);
    const select = screen.getByRole('combobox', { name: 'اختيار المنظمة النشطة' }) as HTMLSelectElement;
    expect(select.value).toBe(orgs[0].id);
    expect(screen.getAllByRole('option')).toHaveLength(2);
  });

  it('stores the selection in the active-organization cookie and refreshes', () => {
    render(<OrganizationSwitcher organizations={orgs} activeId={orgs[0].id} />);
    const select = screen.getByRole('combobox', { name: 'اختيار المنظمة النشطة' });
    fireEvent.change(select, { target: { value: orgs[1].id } });
    expect(document.cookie).toContain(`${ACTIVE_ORG_COOKIE}=${orgs[1].id}`);
    expect(refresh).toHaveBeenCalledTimes(1);
  });
});

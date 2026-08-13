import { describe, expect, it } from 'vitest';
import { organizationSchema } from '../src/features/organizations/schema';
import { projectSchema } from '../src/features/projects/schema';

describe('S0 validation', () => {
  it('requires a meaningful organization name', () => {
    expect(organizationSchema.safeParse({ name: ' ' }).success).toBe(false);
  });
  it('allows only the S0 project payload shape', () => {
    expect(projectSchema.safeParse({
      organizationId: '00000000-0000-4000-8000-000000000001',
      name: 'مشروع النخيل',
      sector: 'REAL_ESTATE',
      internalReference: 'RE-1',
      description: '',
    }).success).toBe(true);
    expect(projectSchema.safeParse({
      organizationId: '00000000-0000-4000-8000-000000000001',
      name: 'مشروع النخيل',
      sector: 'AGRICULTURE',
      internalReference: 'AG-1',
      description: '',
    }).success).toBe(true);
    expect(projectSchema.safeParse({ organizationId: 'bad', name: 'x' }).success).toBe(false);
    expect(projectSchema.safeParse({
      organizationId: '00000000-0000-4000-8000-000000000001',
      name: 'مشروع النخيل',
    }).success).toBe(false);
  });
});

import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { portfolioErrorMessage } from '../src/features/portfolios/errors';
import { PORTFOLIO_STATUS_LABEL } from '../src/features/portfolios/labels';
import {
  assignProjectRpcArguments,
  createPortfolioRpcArguments,
  moveProjectRpcArguments,
  removeProjectRpcArguments,
  transitionPortfolioRpcArguments,
  updatePortfolioRpcArguments,
} from '../src/features/portfolios/rpc';
import {
  assignProjectSchema,
  createPortfolioSchema,
  moveProjectSchema,
  PORTFOLIO_STATUSES,
  portfolioTransitionSchema,
  removeProjectSchema,
  updatePortfolioSchema,
} from '../src/features/portfolios/schema';

const migration = readFileSync(
  'supabase/migrations/20260815030000_r1_portfolio_foundation.sql',
  'utf8',
);
const listPage = readFileSync('src/app/(app)/portfolios/page.tsx', 'utf8');
const detailPage = readFileSync('src/app/(app)/portfolios/[portfolioId]/page.tsx', 'utf8');
const forms = readFileSync('src/app/(app)/portfolios/forms.tsx', 'utf8');

const organizationId = '00000000-0000-4000-8000-000000000001';
const portfolioId = '00000000-0000-4000-8000-000000000002';
const projectId = '00000000-0000-4000-8000-000000000003';
const idempotencyKey = 'r1-app-test-key-001';

const validCreate = {
  organizationId,
  name: 'محفظة النمو',
  description: 'تنظيم مشاريع النمو العقاري',
  responsibleManagerId: '',
  idempotencyKey,
};

describe('R1 portfolio domain contract (management-only parent)', () => {
  it('implements exactly the canonical narrow lifecycle', () => {
    expect(PORTFOLIO_STATUSES).toEqual(['DRAFT', 'ACTIVE', 'ARCHIVED']);
    expect(PORTFOLIO_STATUS_LABEL.DRAFT).toBe('مسودة');
    expect(PORTFOLIO_STATUS_LABEL.ACTIVE).toBe('نشطة');
    expect(PORTFOLIO_STATUS_LABEL.ARCHIVED).toBe('مؤرشفة');
  });

  it('keeps the migration free of investor/legal/economic semantics', () => {
    // Header comments legitimately NAME the forbidden concepts to negate
    // them; strip SQL comments so only schema/mechanics are checked.
    const mechanics = migration
      .split('\n')
      .filter((line) => !line.trimStart().startsWith('--'))
      .join('\n')
      .toLowerCase();
    for (const forbidden of [
      /\bfund_type\b/,
      /\blegal_vehicle\b/,
      /\bnav\b/,
      /\bcommitted_capital\b/,
      /\bsubscribed_capital\b/,
      /\bprofit_share\b/,
      /\bwaterfall\b/,
      /\bcarry\b/,
      /\bmanagement_fee\b/,
      /\breserve\b/,
      /\binvestor/,
      /\bownership\b/,
      /\bunits\b/,
      /\bjsonb\b/,
      /\bcurrency\b/,
    ]) {
      expect(forbidden.test(mechanics), `forbidden token ${forbidden}`).toBe(false);
    }
    // Management-only identity: the only portfolio facts are identity,
    // purpose, lifecycle, and a descriptive manager reference.
    expect(migration).toContain('name text not null');
    expect(migration).toContain('description text');
    expect(migration).toContain("status text not null default 'DRAFT'");
    expect(migration).toContain('responsible_manager_id uuid');
  });

  it('enforces default-deny RLS and authenticated-only SELECT grants', () => {
    expect(migration).toContain('enable row level security');
    expect(migration).toContain('force row level security');
    expect(migration).toContain('for select to authenticated');
    expect(migration).toContain('using (public.is_active_member(organization_id))');
    expect(migration).toContain('revoke all on public.%I from public, anon, authenticated');
  });

  it('keeps one current parent portfolio per project', () => {
    expect(migration).toContain(
      'portfolio_one_current_parent_per_project',
    );
    expect(migration).toContain(
      'on public.portfolio_project_assignments(investment_project_id) where removed_at is null',
    );
  });

  it('enforces organization coherence on both sides of membership', () => {
    expect(migration).toContain(
      'foreign key (portfolio_id, organization_id)',
    );
    expect(migration).toContain(
      'foreign key (investment_project_id, organization_id)',
    );
  });

  it('keeps membership and lifecycle history append-only', () => {
    expect(migration).toContain('raise exception \'portfolio status history is append-only\'');
    expect(migration).toContain('raise exception \'portfolio membership history is append-only\'');
    expect(migration).toContain('raise exception \'portfolio membership facts are immutable\'');
    expect(migration).toContain('raise exception \'portfolio membership removal is final\'');
  });

  it('audits every material command', () => {
    for (const event of [
      'PORTFOLIO_CREATED',
      'PORTFOLIO_METADATA_UPDATED',
      'PORTFOLIO_TRANSITIONED',
      'PROJECT_ASSIGNED_TO_PORTFOLIO',
      'PROJECT_REMOVED_FROM_PORTFOLIO',
      'PROJECT_MOVED_BETWEEN_PORTFOLIOS',
    ]) {
      expect(migration, `missing audit event ${event}`).toContain(`'${event}'`);
    }
  });
});

describe('R1 validation behavior', () => {
  it('accepts a complete portfolio creation payload', () => {
    expect(createPortfolioSchema.safeParse(validCreate).success).toBe(true);
  });

  it('rejects a short portfolio name with an operator message', () => {
    const parsed = createPortfolioSchema.safeParse({ ...validCreate, name: 'أ' });
    expect(parsed.success).toBe(false);
  });

  it('rejects an overlong description', () => {
    const parsed = createPortfolioSchema.safeParse({
      ...validCreate,
      description: 'ط'.repeat(2001),
    });
    expect(parsed.success).toBe(false);
  });

  it('rejects a short client idempotency key', () => {
    const parsed = createPortfolioSchema.safeParse({ ...validCreate, idempotencyKey: 'short' });
    expect(parsed.success).toBe(false);
  });

  it('requires a reason for lifecycle transitions', () => {
    const base = {
      organizationId,
      portfolioId,
      expectedStatus: 'DRAFT' as const,
      newStatus: 'ACTIVE' as const,
      idempotencyKey,
    };
    expect(portfolioTransitionSchema.safeParse({ ...base, reason: 'تنشيط' }).success).toBe(true);
    expect(portfolioTransitionSchema.safeParse({ ...base, reason: 'س' }).success).toBe(false);
  });

  it('only allows canonical lifecycle states in transitions', () => {
    const parsed = portfolioTransitionSchema.safeParse({
      organizationId,
      portfolioId,
      expectedStatus: 'DRAFT',
      newStatus: 'CLOSED',
      reason: 'حالة غير معتمدة',
      idempotencyKey,
    });
    expect(parsed.success).toBe(false);
  });

  it('requires a reason for membership removal and move', () => {
    expect(
      removeProjectSchema.safeParse({
        organizationId,
        portfolioId,
        projectId,
        reason: 'إزالة',
        idempotencyKey,
      }).success,
    ).toBe(true);
    expect(
      removeProjectSchema.safeParse({
        organizationId,
        portfolioId,
        projectId,
        reason: 'س',
        idempotencyKey,
      }).success,
    ).toBe(false);
    expect(
      moveProjectSchema.safeParse({
        organizationId,
        projectId,
        targetPortfolioId: portfolioId,
        reason: 'نقل',
        idempotencyKey,
      }).success,
    ).toBe(true);
  });

  it('requires an explicit project for assignment', () => {
    const parsed = assignProjectSchema.safeParse({
      organizationId,
      portfolioId,
      projectId: 'ليس-معرفا',
      idempotencyKey,
    });
    expect(parsed.success).toBe(false);
  });
});

describe('R1 RPC argument mapping', () => {
  it('maps create inputs onto the database command', () => {
    expect(createPortfolioRpcArguments(validCreate)).toEqual({
      p_organization_id: organizationId,
      p_name: 'محفظة النمو',
      p_description: 'تنظيم مشاريع النمو العقاري',
      p_responsible_manager_id: null,
      p_idempotency_key: idempotencyKey,
    });
  });

  it('maps metadata update inputs onto the database command', () => {
    expect(
      updatePortfolioRpcArguments({
        organizationId,
        portfolioId,
        name: 'اسم محدث',
        description: '',
        responsibleManagerId: '00000000-0000-4000-8000-000000000009',
        idempotencyKey,
      }),
    ).toEqual({
      p_organization_id: organizationId,
      p_portfolio_id: portfolioId,
      p_name: 'اسم محدث',
      p_description: null,
      p_responsible_manager_id: '00000000-0000-4000-8000-000000000009',
      p_idempotency_key: idempotencyKey,
    });
  });

  it('maps transition, assign, remove, and move inputs onto their commands', () => {
    expect(
      transitionPortfolioRpcArguments({
        organizationId,
        portfolioId,
        expectedStatus: 'DRAFT',
        newStatus: 'ACTIVE',
        reason: 'تنشيط',
        idempotencyKey,
      }).p_expected_status,
    ).toBe('DRAFT');
    expect(
      assignProjectRpcArguments({ organizationId, portfolioId, projectId, idempotencyKey })
        .p_project_id,
    ).toBe(projectId);
    expect(
      removeProjectRpcArguments({
        organizationId,
        portfolioId,
        projectId,
        reason: 'إزالة',
        idempotencyKey,
      }).p_reason,
    ).toBe('إزالة');
    expect(
      moveProjectRpcArguments({
        organizationId,
        projectId,
        targetPortfolioId: portfolioId,
        reason: 'نقل',
        idempotencyKey,
      }).p_target_portfolio_id,
    ).toBe(portfolioId);
  });
});

describe('R1 operator-facing error mapping', () => {
  it('maps database guard messages to operator Arabic', () => {
    expect(portfolioErrorMessage(new Error('projects can only be assigned to an active portfolio')))
      .toContain('محفظة نشطة');
    expect(portfolioErrorMessage(new Error('project already assigned to a portfolio')))
      .toContain('مُسند بالفعل');
    expect(portfolioErrorMessage(new Error('invalid portfolio transition: ARCHIVED -> ACTIVE')))
      .toContain('غير مسموح');
    expect(portfolioErrorMessage(new Error('archived portfolio metadata is read-only')))
      .toContain('للقراءة فقط');
    expect(portfolioErrorMessage(new Error('idempotency key payload mismatch')))
      .toContain('حدّث الصفحة');
    expect(portfolioErrorMessage(new Error('forbidden'))).toContain('صلاحية');
  });

  it('never leaks unknown internals to the operator', () => {
    expect(portfolioErrorMessage(new Error('could not embed the context object into the plan')))
      .not.toContain('context object');
  });
});

describe('R1 UI integration (Arabic/RTL, shallow navigation, honest states)', () => {
  it('lives inside the existing app shell navigation', () => {
    // Primary navigation lives in the shared AppNav rendered by the app layout.
    const layout = readFileSync('src/app/(app)/layout.tsx', 'utf8');
    const nav = readFileSync('src/shared/ui/app-nav.tsx', 'utf8');
    expect(layout).toContain('<AppNav');
    expect(nav).toContain("href: '/portfolios'");
    expect(nav).toContain('المحافظ');
  });

  it('shows honest empty and guidance states without fake numbers', () => {
    expect(listPage).toContain('لا توجد محافظ بعد');
    expect(listPage).toContain('لن نعرض أرقامًا');
    expect(listPage).toContain('بيانات تجريبية');
    // R1 shows no financial roll-ups at all.
    expect(listPage).not.toContain('NAV');
    expect(detailPage).not.toContain('موزعة');
  });

  it('navigates Portfolio → Project → existing project workspace (no duplicate workspace)', () => {
    expect(detailPage).toContain('sectorLandingHref');
    // The existing project workspace is the destination; R1 adds no
    // project-duplicate route.
    expect(detailPage).not.toContain('/projects/${m.investment_project_id}/portfolio');
  });

  it('keeps lifecycle explicit and controlled in the UI', () => {
    expect(detailPage).toContain('تنشيط المحفظة');
    expect(detailPage).toContain('أرشفة المحفظة');
    expect(detailPage).toContain('أرشفة المسودة');
    expect(forms).toContain('expectedStatus');
    expect(forms).toContain('newStatus');
  });

  it('renders membership management in Arabic with removal history', () => {
    expect(detailPage).toContain('المشاريع المُسندة');
    expect(detailPage).toContain('سجل الإسنادات السابقة');
    expect(detailPage).toContain('سجل حالات المحفظة');
    expect(forms).toContain('إزالة المشروع من المحفظة');
    expect(forms).toContain('نقل المشروع إلى محفظة أخرى');
    expect(forms).toContain('إسناد المشروع إلى المحفظة');
  });

  it('uses the canonical client idempotency-key lifecycle hook', () => {
    expect(forms).toContain('useCommandIdempotencyKey');
    expect(forms).toContain('@/shared/idempotency/use-command-idempotency-key');
  });
});

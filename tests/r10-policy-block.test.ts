import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const investorPage = readFileSync('src/app/(app)/projects/[projectId]/investors/page.tsx', 'utf8');
const statementsPage = readFileSync('src/app/(app)/projects/[projectId]/statements/page.tsx', 'utf8');
const overviewPage = readFileSync('src/app/(app)/projects/[projectId]/overview/page.tsx', 'utf8');
const decisions = readFileSync('docs/OPEN_BUSINESS_DECISIONS.md', 'utf8');

describe('R10 keeps unresolved investor economics inert until R14', () => {
  it('keeps the canonical business decisions open', () => {
    for (const id of ['BD-003', 'BD-004', 'BD-006', 'BD-008']) {
      expect(decisions).toMatch(new RegExp(`\\| ${id} \\| OPEN \\|`));
    }
  });

  it('does not import entitlement runtime from the investor surface', () => {
    expect(investorPage).not.toMatch(/features\/allocation/);
    expect(investorPage).not.toMatch(/ConfigureRulesForm|PrepareAllocationForm|ApproveAllocationForm/);
    expect(investorPage).not.toMatch(/PrepareDistributionForm|ApproveDistributionForm|PayDistributionForm/);
    expect(investorPage).not.toMatch(/getDistributionCapacity|getPartnerCapitalStatement|getAllocation/);
  });

  it('states the policy block explicitly instead of silently showing zeros', () => {
    expect(investorPage).toContain('Policy Blocked — BD-003 / BD-004 / BD-006 / BD-008');
    expect(investorPage).toContain('لا يعرض Terranex حاليًا نسبة ملكية');
    expect(investorPage).toContain('أي حقل entitlement أو allocation أو distribution يظل غير فعال حتى R14');
  });

  it('allows identity and agreement transparency without inferring economics', () => {
    expect(investorPage).toContain('getParticipants');
    expect(investorPage).toContain('getActiveVersion');
    expect(investorPage).toContain('الهوية المسجلة لا تعني تلقائيًا ملكية أو entitlement أو حصة في الربح');
  });

  it('redirects the legacy partner statement surface to the safe R10 page', () => {
    expect(statementsPage).toMatch(/redirect\(`\/projects\/\$\{projectId\}\/investors`\)/);
    expect(statementsPage).not.toMatch(/getPartnerCapitalStatement|formatMinorUnits|features\/allocation/);
  });

  it('keeps distribution economics out of the project overview', () => {
    expect(overviewPage).not.toMatch(/getDistributions|approvedDistributions|paidDistributions/);
    expect(overviewPage).toContain('BD-006 وBD-008');
    expect(overviewPage).toContain('ليست حصة مستثمر');
  });
});

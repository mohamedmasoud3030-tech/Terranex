import { describe, expect, it } from 'vitest';

import { projectIssues, signalIssues, sortIssues, verdictAr } from '@/features/health/checks';

describe('company health check', () => {
  it('turns overdue obligations into a critical issue with a link to the costs page', () => {
    const issues = projectIssues({
      projectId: 'p1', projectName: 'مشروع النخيل',
      overdueObligations: 2, disputedObligations: 0, unreconciledInflowCount: 0,
    });
    expect(issues).toHaveLength(1);
    expect(issues[0].severity).toBe('CRITICAL');
    expect(issues[0].href).toBe('/projects/p1/costs');
    expect(issues[0].messageAr).toContain('مشروع النخيل');
    expect(issues[0].messageAr).toContain('متأخر');
  });

  it('flags unreconciled bank inflows and links to the cash page', () => {
    const issues = projectIssues({
      projectId: 'p1', projectName: 'مزرعة الوادي',
      overdueObligations: 0, disputedObligations: 0, unreconciledInflowCount: 3,
    });
    expect(issues).toHaveLength(1);
    expect(issues[0].href).toBe('/projects/p1/cash');
    expect(issues[0].messageAr).toContain('لم تُطابَق');
  });

  it('maps integrity signals to their project integrity page', () => {
    const issues = signalIssues([
      { projectId: 'p9', signalLabelAr: 'سطور بنكية غير مطابقة', severity: 'CRITICAL', subjectCount: 3 },
    ]);
    expect(issues[0].href).toBe('/projects/p9/integrity');
    expect(issues[0].messageAr).toContain('سطور بنكية غير مطابقة');
  });

  it('sorts critical issues first and phrases the verdict honestly', () => {
    const sorted = sortIssues([
      { severity: 'INFO', messageAr: 'x', href: '/', actionAr: 'y' },
      { severity: 'CRITICAL', messageAr: 'x', href: '/', actionAr: 'y' },
    ]);
    expect(sorted[0].severity).toBe('CRITICAL');
    expect(verdictAr([])).toContain('لا توجد مشاكل');
    expect(verdictAr(sorted)).toContain('حرجة');
  });

  it('keeps clean projects silent', () => {
    expect(projectIssues({
      projectId: 'p1', projectName: 'سليم',
      overdueObligations: 0, disputedObligations: 0, unreconciledInflowCount: 0,
    })).toHaveLength(0);
  });
});

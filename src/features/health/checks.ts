// Company health check — plain-Arabic answers to "what is wrong or missing?"
//
// Every check reads an existing read model (integrity signals, project
// position, bank statement line status). Nothing here recomputes finance in
// React; the module only turns existing facts into a sentence and a link to
// the page where the fact is fixed.

export type HealthSeverity = 'CRITICAL' | 'WARNING' | 'INFO';

export interface HealthIssue {
  readonly severity: HealthSeverity;
  /** One plain-Arabic sentence: what is wrong and why it matters. */
  readonly messageAr: string;
  /** Where the operator fixes it. */
  readonly href: string;
  readonly actionAr: string;
}

export interface HealthProjectInput {
  readonly projectId: string;
  readonly projectName: string;
  readonly overdueObligations: number;
  readonly disputedObligations: number;
  readonly unreconciledInflowCount: number;
}

export interface HealthSignalInput {
  readonly projectId: string | null;
  readonly signalLabelAr: string;
  readonly severity: HealthSeverity;
  readonly subjectCount: number;
}

const SEVERITY_ORDER: Record<HealthSeverity, number> = { CRITICAL: 0, WARNING: 1, INFO: 2 };

export function sortIssues(issues: readonly HealthIssue[]): HealthIssue[] {
  return [...issues].sort((a, b) => SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity]);
}

/** Integrity signals become issues as-is: the read model already speaks Arabic. */
export function signalIssues(signals: readonly HealthSignalInput[]): HealthIssue[] {
  return signals.map((signal) => ({
    severity: signal.severity,
    messageAr: `${signal.signalLabelAr} — ${signal.subjectCount} ${signal.subjectCount === 1 ? 'حالة' : 'حالات'} تحتاج مراجعة.`,
    href: signal.projectId ? `/projects/${signal.projectId}/integrity` : '/reports',
    actionAr: 'راجع الإشارة',
  }));
}

export function projectIssues(project: HealthProjectInput): HealthIssue[] {
  const issues: HealthIssue[] = [];
  const base = `/projects/${project.projectId}`;
  if (project.overdueObligations > 0) {
    issues.push({
      severity: 'CRITICAL',
      messageAr: `مشروع «${project.projectName}»: ${project.overdueObligations} ${project.overdueObligations === 1 ? 'التزام متأخر' : 'التزامات متأخرة'} عن تاريخ الاستحقاق — تأخيرها يشوّه صورة السيولة.`,
      href: `${base}/costs`,
      actionAr: 'سدّد أو أعد الجدولة',
    });
  }
  if (project.disputedObligations > 0) {
    issues.push({
      severity: 'WARNING',
      messageAr: `مشروع «${project.projectName}»: ${project.disputedObligations} ${project.disputedObligations === 1 ? 'التزام متنازع عليه' : 'التزامات متنازع عليها'} لم تُحسم.`,
      href: `${base}/costs`,
      actionAr: 'راجع النزاع',
    });
  }
  if (project.unreconciledInflowCount > 0) {
    issues.push({
      severity: 'WARNING',
      messageAr: `مشروع «${project.projectName}»: ${project.unreconciledInflowCount} ${project.unreconciledInflowCount === 1 ? 'حركة بنكية واردة' : 'حركات بنكية واردة'} لم تُطابَق مع أي قيد — الأموال دخلت البنك ولا يعرف النظام مصدرها.`,
      href: `${base}/cash`,
      actionAr: 'طابِق الحركات',
    });
  }
  return issues;
}

/** One-line verdict for the header. */
export function verdictAr(issues: readonly HealthIssue[]): string {
  if (issues.length === 0) return 'لا توجد مشاكل مفتوحة — السجل سليم حسب الفحوص الحالية.';
  const critical = issues.filter((issue) => issue.severity === 'CRITICAL').length;
  if (critical > 0) return `${critical} ${critical === 1 ? 'مشكلة حرجة' : 'مشاكل حرجة'} من أصل ${issues.length} — ابدأ بها فورًا.`;
  return `${issues.length} ${issues.length === 1 ? 'ملاحظة تحتاج' : 'ملاحظات تحتاج'} انتباهك، ولا شيء حرج.`;
}

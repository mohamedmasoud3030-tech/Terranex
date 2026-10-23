# Terranex — Status

> Canonical state file (2026-10-22, single-source consolidation). Execution
> detail: `GREENFIELD_EXECUTION.md`. Roadmap: `ROADMAP_R0_R17.md`. Open
> owner items: `OPEN_BUSINESS_DECISIONS.md`.

## Product

Arabic web application for private investment-company operations:
Organization → Investment Portfolio → Investment Project → sector facts
(Real Estate / Agriculture / Livestock) + finance facts + evidence —
operations, procurement, obligations/payments, bank reconciliation,
double-entry finance, period close, risk and decisions in one system.

## Verified state

- `main` CI is green end-to-end for the first time (PR #187, 2026-10-22):
  vitest 1104/1104, lint, typecheck, build, route-review, and the full
  `scripts/db-test.sh` migration replay + SQL/concurrency suites. The four
  root causes are recorded in that PR (moved execution file, S6/S2 date
  drift, reopen boundary chain, forward-upgrade fixture cutoffs).
- All three sector paths are technically implemented for their authorized
  scopes; the historical sector-expansion sequence closed at GF-024
  (see `GREENFIELD_EXECUTION.md`); the active roadmap is R0–R17 with a
  hard stop at R13.
- The four long-frozen PRs were dispositioned 2026-10-22: #181, #185,
  #186 merged; #180 closed as superseded by #187.

## Open items

- Real-customer validation, buyer UAT and commercial evidence: not
  started / not passed (implementation, deployment and customer evidence
  are kept separate — see `GREENFIELD_EXECUTION.md`).
- Owner decisions pending in `OPEN_BUSINESS_DECISIONS.md` and the R14
  target-company pack (`specs/owner/`).
- Pilot activation path: `pilot-readiness/` (intake → UAT → GA backlog).

## Documentation map

Root `README.md` + `AGENTS.md`; `docs/` canonical files above + `decisions/`
register + living specs under `docs/specs/`, `greenfield/`, `runbooks/`,
`pilot-readiness/`, `design/`, `demo/`, `agent-os/`. Removed 2026-10-22:
dated execution/audit/status reports — Git history is the archive.

---

## 🛰️ مراجع الموجات الإدارية — مزامنة مركز القيادة (2026-10-23)

آخر ثلاث موجات إدارية اكتملت على هذا المستودع بدمج موثق — هذا القسم هو الصفحة الأخيرة من رحلة «خطة ← تسليم»:

| الموجة | PR | مرجع الدمج | التاريخ | الأثر |
|---|---|---|---|---|
| توحيد المستندات القانونية | #189 | `edcf0d8` | 2026-10-22 | القانونية الثلاثية + specs + القرار 0035 موثق |
| ربط مركز القيادة | #190 | `dea39c2` | 2026-10-23 | 🛡️ إزالة .env.production + ربط المركز |
| مزامنة المهارات | #191 | `eb44bcf` | 2026-10-23 | 19 مهارة مرجعية بعد المزامنة |

> **المرجع الأم للمحفظة:** مركز القيادة [`command-center-`](https://github.com/mohamedmasoud3030-tech/command-center-) — سجل الجلسات النشطة والـ PRs المفتوحة وقرارات المالك يعيش هناك. هذا القسم يحدّثه مدير المحفظة مع كل موجة ولا يُعدّل يدوياً.

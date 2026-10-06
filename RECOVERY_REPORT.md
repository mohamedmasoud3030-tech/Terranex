# Terranex Recovery Report

**Authoritative branch:** `arena/4c002d8d-terranex`
**Base:** `main` @ `5156a51` ("reconcile: merge H1 truth panels into current interface (#178)")
**Tip:** `5f0065b` — `5156a51` → `0676941` → `3b0bfd3` → `5f0065b`
**Date of evidence:** 2026-10-06
**Working tree at close:** clean (`git status --short` empty, remote = local)

Gates at tip: `tsc --noEmit` clean · `eslint .` exit 0 · **76 test files / 1104 tests passing** · `npm run build` clean · five design generators `--check`-current with zero writes · runtime harness **14 routes, all assertions passed**.

---

## A. Repository Truth

**What the repository actually is.** A Next.js 16 / React 19 / Supabase (Postgres) application, package `terranex` v1.0.0, 33 route surfaces (`page.tsx`), 106 migrations, 112 database test suites, 76 Vitest files. It is a real-estate / agriculture / livestock investment-organisation back office: projects, funding agreements and capital, cost obligations and cash, revenue, realized results, procurement, governance, close.

**The repo is fragmented historical work, and `main` is not the whole story.** This was confirmed, not assumed:

| Question | Finding | Evidence |
|---|---|---|
| Is `main` current? | **No.** `main` was stale and is still behind the recovered content. | `main` = `arena/01a06a68` = `reconcile/h1-ui-20260919` = `5156a51`; 1005 commits, 22 remote heads |
| Is the newest commit the best? | **No.** Recency and completeness diverge — see B/C. | branch comparison below |
| Was there important work outside `main`? | **Yes, in three places.** | `archive/design-ui-ux-upgrade-20260919` (`486b32a`), `archive/h1-ui-reconciliation-source-20260919` (`c4d49eb`), `integrate/h1-core` (`4ad6c56`) |
| Was work completed but never merged? | **Yes.** PR **#176** was closed with head `486b32a` while its branch was reset to `9c76925` — the design-layer work was completed and the PR was closed rather than merged. | `gh pr view 176` |

**History-loss event, and why it did not cost us anything.** The sandbox was reset mid-session: `git log` shows only `5156a51` (shallow clone) and the four follow-on commits (`cec9177`, `a8a788b`, `a0afbc5`, `0b132be`) became unreachable locally. Their **content survived in the working tree** and was re-committed as `0676941`, which is why the tip commit is a single coherent recovery commit rather than five. No history was rewritten or force-pushed at any point; the pre-existing shared history is intact and untouched.

**A note on the tracking/reference issue and the `b19f2de` clue.** The historical clues given (a tracking/reference issue; previous local HEAD `b19f2de`) were checked: they belong to the pre-reset local state and are not reachable in the current shallow clone. Everything they were said to contain was independently recovered from the working tree and the archive branches, so nothing is outstanding from them — but the report states this explicitly rather than claiming the objects were found.

### Branch / commit divergence map

```
main ══ arena/01a06a68 ══ reconcile/h1-ui-20260919 ══ 5156a51   (base of this branch)
                                                             └─ 0676941 → 3b0bfd3 → 5f0065b  ← arena/4c002d8d-terranex
integrate/h1-core ══ agent/terranex-agent-os-skills ══ 4ad6c56   (H1 domain core, merged into main via #177/#178)
design/ui-ux-upgrade ══ fix/gf017 ══ legacy/pre-greenfield ══ 9c76925   (design layer, left behind when #176 closed)
archive/design-ui-ux-upgrade-20260919 ══ 486b32a               (PR #176 head — the completed design work)
archive/h1-ui-reconciliation-source-20260919 ══ c4d49eb        (H1 UI reconciliation source)
demo/real-estate-showcase-data ══ d5885d1                      (showcase fixtures only)
```

---

## B. Recovered Work

**Recovery rule applied:** *H1 domain semantics win; design presentation wins.* The two layers were built independently and neither branch had both. They were combined by content, not by merging branch tips (`integrate/h1-core`'s domain core had already reached `main` through #177/#178; the design layer had not reached `main` at all).

**Recovered by content and now integrated:**

- **H1 / ADR-0034 result truth** — `docs/decisions/0034_H1_PROJECT_RESULT_TRUTH_AND_PROJECT_BRIEF.md` plus migrations `20260904010000`…`20260904010600` and suites `100`/`101`/`102`; primitives `funding/project-capital.ts`, `result/project-result.ts`, `result/qualified-result.ts` (`RESULT_TERM_AR = 'نتيجة التشغيل الإدارية'`); the per-currency read models `project_cash_by_currency_read`, `project_capital_by_currency_read`, `project_result_by_currency_read`.
- **The design layer from `archive/design-ui-ux-upgrade-20260919`, extracted selectively** — `docs/design/*`, `public/`, `src/shared/ui/{auth,route-error,sector}.tsx`, `src/features/workspace/sectors.ts`, route-level `error.tsx` and `loading.tsx` boundaries (59 files: 29 `error.tsx`, 30 `loading.tsx`), the section-22 stylesheet block in `src/app/globals.css`, and the five design generators. **This was not merged wholesale** — see §H.
- **Four recovered money read models**, which are the reason two whole surfaces were previously invisible in the harness: `property_cost_control_read`, `property_cost_drilldown_read`, `project_financial_position_read`, `approval_exception_registry_read` (`scripts/ui-preview/fixtures.mjs`, populated fixtures 29 → 33 keys, locked by `tests/ui-preview-fixtures.test.ts`, 16/16).

**Unreachable/unrecoverable:** the four pre-reset local commits as *objects* (content recovered), and any local state from `b19f2de` not represented in the working tree or archives.

### Classification of significant changes

| Class | Meaning | Items |
|---|---|---|
| **A** correct + integrated | | H1 result truth + ADR-0034; the three `*ByCurrency` contracts; `src/shared/money/by-currency.ts`; the design layer (docs/public/ui/error+loading); `getProjectPosition` singleton semantics; the repaired `/overview /revenue /cash /costs /budget /funding /operations /integrity` surfaces |
| **B** correct, not integrated | | PR #176's branch as a *branch* (work integrated by content); S5 allocation/distribution readers — **no `/allocation` or `/distribution` route exists**, so `DistributionCapacity` and friends are unreachable by any user; `s5_rule_sets_read` |
| **C** correct, incomplete | | `/close` — `ClosedPeriodCard` still receives `gates` and `exceptions` props that are never rendered (§D); intake `drafts` and `draftVersions` locals indicate a dropped drafts view |
| **D** implemented, insufficiently verified | | all 106 migrations / 112 DB suites — **`npm run db:test` cannot run in this environment** (no `psql`/`pg_dump`/`docker`), so DB claims are "unverified by execution"; `scripts/ui-preview/snapshot.mjs` (needs chromium, absent) |
| **E** duplicated | | the three functional-duplicate scalar readers (`getProjectCapitalPosition`, `getProjectOperatingResult`, and the position scalar path) — now removed as TS readers; their **views are retained deliberately** |
| **F** obsolete | | five superseded legacy copies of the costs command forms; 12 dead imports; the superseded "current baseline" figures in six audit documents |
| **G** incorrect | | the class-G pattern: summing `*_minor_units` rows that each carry their own currency, then formatting the total with `project.reporting_currency`; the two invalid-singleton readers; three manufactured-money surfaces |
| **H** planned only | | no `/allocation` or `/distribution` UI; close-run gates/exceptions UI |

---

## C. Current Architecture

**Domain contract → typed roll-up → view model → UI.** The recovered architecture enforces currency safety in the domain layer, not in formatting:

- **`src/shared/money/by-currency.ts` is the only sanctioned money roll-up.** It returns a *list keyed by currency*, never a scalar. `addSameCurrency` throws `refusing to add X to Y`. There is no function that returns a bare amount string, so a cross-currency total cannot be expressed by a page that uses it.
- **Per-currency read models are the SQL contract.** `project_cash_by_currency_read`, `project_capital_by_currency_read`, `project_result_by_currency_read` each return one row per `(project, currency)`.
- **The reporting-currency slice views are a deliberate, documented exclusion.** `project_financial_position_read` is driven by `investment_projects` and joins each CTE `on <x>.project_id = p.id and <x>.currency = p.reporting_currency` (definition at `20260816060000_r5_basic_property_rental_income.sql:660-730`, earlier `20260816056000:15`, `20260816058000:1316`). Its one-row-per-project guarantee is therefore **true**, and `.maybeSingle()` on it is correct — but the row *is* the reporting-currency slice, with other-currency facts `coalesce`d to zero. That is a SQL-contract limitation of the same shape as `project_operating_result_read`; `/integrity` now discloses it in the UI ("نطاق هذا الجدول عملة تقارير المشروع" / "يستبعد ما رُحّل بعملة أخرى").
- **Consolidation is explicit about conversion.** `organization_financial_consolidation_read` (`20260816057000_f10_portfolio_rollup.sql:150`) carries `fx_status ∈ {NO_REPORTING_CURRENCY, SAME_CURRENCY, NO_RATE_SNAPSHOT, CONVERTED_AT_RATE}`; `per_currency` groups `(organization_id, currency, org_reporting_currency)`; `consolidated` nulls native amounts unless single-currency with `org_reporting_currency is null`, and fills `converted_*` only when no row is `NO_RATE_SNAPSHOT`; `union all` emits `BY_CURRENCY` then `CONSOLIDATED`.

### The class-G defect, and why the repair is structural

The legacy defect summed rows of different currencies and stamped the total with one currency — the symptom was `100,000,000 EGP + 5,000,000 OMR` presenting as a single `105000000`. Repaired in `/overview`, `/revenue`, `/cash`, `/costs`, `/budget`, `/funding`, `/operations`, `/integrity`. `/budget` uses the row's own currency at 14 sites and `reporting_currency` only in the subtitle. `/integrity` routes every amount through a single `moneyCell(amount, rowCurrency)` guard that renders `—`, `— (مبلغ بلا عملة معلنة)`, or `— (… بعملة غير مدعومة: …)`.

**The safety is structural, not conventional.** There is no code path in the repaired surfaces that *can* add two currencies: the roll-up primitive refuses, and the per-currency SQL contract never returns a mixed row. A developer who wants a cross-currency number must remove a type and a SQL grouping — not merely forget a convention.

**Two invalid singletons were real; one suspected case was a false positive.** `getCurrentMembership` filtered only by organisation while `membership_read` exposes every active member's row and `memberships` is `unique(organization_id, user_id)` — any organisation with a second member made `.maybeSingle()` return `406 PGRST116` and broke 18 project pages. Fixed by filtering to the caller (`auth.getUser()`). `getDistributionCapacity` selected a per-currency view with `.maybeSingle()`; now returns an array ordered by `currency`. The suspected third — `getProjectPosition` — was **correct as written** and was left alone except for a docstring recording the exclusion.

---

## D. Correctness Status

**Correct and verified by execution:** the repaired page surfaces (runtime harness, 14 routes); the roll-up primitive (`tests/money-by-currency.test.ts`); the singleton contracts (`tests/financial-singleton-contracts.test.ts`, 11 tests); the currency-safety page contract (`tests/currency-safe-pages.test.ts`, now 42 tests).

**Correct but verified only by static analysis:** all SQL view definitions. `npm run db:test` cannot run here — no `psql`, `pg_dump`, or `docker`. Every database claim in this report is marked **unverified by execution**.

**Three surfaces were still inventing money, and are now repaired** (commit `3b0bfd3`) — this was the finding of the final sweep, and it is worth stating plainly because all three produced *plausible* numbers rather than errors:

1. **`/intake`** rendered an absent variance as `0.00`. A null `debit_variance_minor_units` means the variance is unknown; printing zero asserts the opening import reconciles perfectly — the opposite of the truth.
2. **Home's sector table** defaulted a missing row to `0.00` for the cost deducted from the result, asserting nothing was deducted.
3. **`/procurement`** showed `invoiced = 0.00` and `remaining = commercial total` for any order without a commitment row. `project_procurement_commitments_read` emits a row only for an `APPROVED` order with at least one line (`where o.status = 'APPROVED'`, inner join on the lines) — so for a DRAFT or SUBMITTED order the UI asserted a recognised purchase commitment and a fully-outstanding balance that do not exist.

**Correction to a natural but wrong reading of `/intake`:** its `formatMinorUnits(value, project.reporting_currency)` is **correct**, not a class-G stamp. The S7 intake contract carries no per-row currency (`project_intake_declarations` has `*_minor_units` columns and no currency column; S7 amounts derive from the project's `reporting_currency`). Recorded in-code so it is not "fixed" later.

**Left in place deliberately — evidence, not cleanup targets.** Four `TS6133` findings remain and are *not* removed, because deleting them would erase the trace of work that was dropped:
- `drafts` (`budget`), `draftVersions` (`intake`) — a drafts view that was never finished.
- `gates` + `exceptions` props of `ClosedPeriodCard` (`close`) — a close-run gates/exceptions UI that was dropped.

These are reported as **Class C** work, not silently tidied away.

---

## E. UI-UX Status

**The port-4173 problem, correctly diagnosed.** A previous preview appeared to work while showing the wrong thing: `scripts/serve-design-gallery.mjs` (default port **4173**) serves the *static* `docs/design/design-system.html`. A 4173 response, a directory listing, or a long-lived dev server is **not** app-preview evidence. Only the `npm run dev` app plus the mock Supabase harness is authoritative. The app preview binds `0.0.0.0:3000`; the mock binds `127.0.0.1:54329`.

**Preview configuration, verified.** `next.config.ts` carries `allowedDevOrigins: ['*.e2b.app', 'localhost:3000', '127.0.0.1:3000']` (without it the sandbox preview host is rejected). Framing policy is **dev-only**: production emits `X-Frame-Options: DENY` and no `frame-ancestors` — proven from `.next/routes-manifest.json`, cross-checked against `next.config.ts` where the CSP `frame-ancestors` branch is dev-only. `/_next/hmr` returning `307` is a normal redirect, not a fault.

**Harness credentials and rationale documented.** `scripts/ui-preview/README.md` now records sign-in, the pinned-token rationale (`preview-access-token-static` / `preview-refresh-token-static` — pinned on purpose, because `--print-cookie` otherwise randomises per process), the cookie-jar `curl` example, and the authoritative-preview boundary. `MOCK_SCENARIO=empty` exercises first-use states.

**Design-layer recovery was selective.** The archive's presentation work was taken where it was additive (route error/loading states, sector labelling, auth/route-error UI, the design gallery and its generators) and **not** taken where it would have fought the domain layer — the H1 truth panels and the currency-safe presentation shape were kept from the domain side. No wholesale merge.

---

## F. Test Status

**76 files / 1104 tests passing** at tip — 60 `.test.ts` plus 16 `.test.tsx`, every one of them under `tests/` (verified with `find tests -name '*.test.ts*'`; an earlier `ls tests/*.test.ts` undercounted at 60 by missing the `.tsx` suites). Composition:

- **Real evidence** — `currency-safe-pages.test.ts` (42), `financial-singleton-contracts.test.ts` (11), `money-by-currency.test.ts`, `workspace.test.ts` (42), `ui-preview-fixtures.test.ts` (16), `project-{capital,cash,result}-by-currency`, `qualified-result`, `executive-home`, `section-labelling`, `design-system`, `login-redirect`, `proxy-auth`. These assert contracts: a currency mismatch throws, a singleton is pinned to the constraint that makes it valid, a fixture set stays multi-currency.
- **Stale/obsolete tests removed** — the tests that pinned the removed scalar readers and the five legacy form copies were updated to the surviving contract, not preserved for their own sake.
- **No test was weakened or deleted to reach green.** Where an assertion could not pass, the *product* was examined first; that is how the item-10 runtime question was resolved — the product was correct and the harness's expectation was wrong (see below).

**Negative-case coverage, with non-vacuity proven by mutation.** The new block in `currency-safe-pages.test.ts` pins the *class* rather than the instances: no `*_minor_units ?? '0'`, and no `a_minor_units ?? b_minor_units` substitution. It is scoped to `*_minor_units` deliberately — these pages legitimately use `?? '0'` for quantities and counts (`received_quantity`, rejected-row counts) and `?? null` for an absent variance, and those must not be swept up. Reintroducing each defect in turn failed **1, 2 and 5** assertions respectively; reverting the repairs entirely failed **6**.

**A harness error that looked like a product bug.** `/tmp/verify-runtime.py` initially failed. The product was never wrong: the harness's normaliser **strips** `٬` (the Arabic thousands separator), so its expected literals had to be the separator-stripped forms (`9400000.00`, `12000.000`, `12545000.00`). Scale is now additionally pinned by regexes (OMR 3 decimals, EGP 2 decimals). The correct response was to fix the harness, never the pages.

**DB suites: 112, none executed here.** Report as *unverified by execution*, never "passes".

---

## G. Interview Claim Status

There is **no interview-claim document in the repository** — the only `interview` references are ADR 0001 product strategy. The matrix below therefore evaluates the claims as they stand in the project's own documentation, which is where an interviewer would read them.

| Claim | Evidence | Status | Required correction |
|---|---|---|---|
| Arabic RTL interface | `src/app/layout.tsx` has `lang="ar" dir="rtl"` | **VERIFIED** | none |
| Currency-safe money handling | `src/shared/money/by-currency.ts` + 8 repaired surfaces + 42 contract tests + runtime harness | **VERIFIED** | none |
| No silent cross-currency aggregation | `formatMinorUnits` never called on a mixed total in `src/`; no `parseFloat(`/`Number(` on money; structural primitive | **VERIFIED** | none |
| Row-level security on every table | every table is forced to RLS — **51 distinct tables** by a static `alter table … force row level security`, plus **25 migrations** that iterate a table array with `execute format('alter table public.%I force row level security', t)`; 73 policy expressions reference `is_active_member(organization_id)` | **PARTIALLY VERIFIED** | static only — `db:test` cannot run here; coverage is asserted by reading 106 migrations, not by executing them |
| "1095 tests passing" (as written in `AI_PROJECT_STATUS.md`) | was accurate at the time of the pre-cleanup run | **PARTIALLY VERIFIED** | corrected to the current figure; counts drift |
| 99 migrations / 108 db suites (as written in the audit docs) | actual: **106 migrations / 112 db suites** | **FALSE-MISLEADING as a current claim** | historical banners added; superseded figures re-labelled |
| 74 files / 1061 tests (as written in `AI_PROJECT_ASSESSMENT.md`) | actual: 76 / 1104 | **FALSE-MISLEADING as a current claim** | corrected |
| Database correctness | no DB execution possible in this environment | **UNSUPPORTED here** | must be stated as unverified by execution |
| S5 allocation/distribution capability | readers exist, **no `/allocation` or `/distribution` route** | **UNSUPPORTED as a user-facing feature** | Class B — do not present as delivered |

**No claim was rewritten to sound better.** Where a claim was wrong, the *document* was corrected toward the code and the historical figures were preserved behind a banner, not deleted.

---

## H. Cleanup

Every deletion in this recovery is evidence-justified. Nothing was removed because it looked unused.

**Removed:**
- **Three dead scalar readers** — `getProjectCapitalPosition`/`ProjectCapitalPosition` and `getProjectOperatingResult`/`ProjectOperatingResultRow`: no production consumer. **Their views are retained deliberately** — `project_operating_result_read` is consumed at project grain by the S6/H1 gates (`20260904010600:19-24`), and `project_capital_position*` is a cross-currency aggregate pinned by an S6 gate and not command-reachable; its grain must not change.
- **Five superseded legacy copies of the costs command forms** — the page already imported the retry-safe versions and nothing referenced the old ones. They must not be re-added to the `./forms` import.
- **11 unused symbols resolved** under anchor assertions — `tsc --noEmit --noUnusedLocals --noUnusedParameters` went from **15 `TS6133` findings to 4**, and the 4 survivors are the Class-C evidence markers named in §D (verified by re-running the check: exactly `drafts`, `draftVersions`, `gates`, `exceptions` remain).
- **Obsolete documentation figures** — superseded by current baselines, with historical banners added to `FULL_PROJECT_AUDIT.md`, `PROJECT_DEFECTS.md`, `PROJECT_COMMANDS.md`, `ARCHITECTURE.md`, `GREENFIELD_EXECUTION.md`, `docs/PRE_OWNER_POLICY_AUDIT.md`.

**One authoritative implementation per responsibility** — no parallel implementations remain for money roll-up, per-currency reads, or the costs forms.

**No generated or ignored artifact is committed:** `git status --porcelain` shows no `.next/`, `node_modules/`, `*.log`, or `next-env.d.ts`. `npm run dev` rewrites `next-env.d.ts`; it was restored before every commit.

**A correction to one over-hasty note:** `project_cost_control_read` **does not exist** anywhere — the relation is `property_cost_control_read`. Any note naming the former is wrong.

---

## I. Remaining Risks

1. **Database correctness is unverified by execution.** 106 migrations and 112 suites, including all RLS policy claims, are static-analysis-only in this environment. This is the single largest unclosed verification gap and it is a *limitation of the environment*, not a known defect. It needs a Postgres-capable runner.
2. **`project_financial_position_read` and `project_operating_result_read` are reporting-currency slice views.** Correct per their SQL contract, but silently exclude other-currency facts. The per-currency contracts exist and `/integrity` discloses the scope; the views themselves have not been re-grained (the S6 gates consume their current grain).
3. **Class-C dropped UI:** the close-run gates/exceptions UI (`gates`/`exceptions` props on `ClosedPeriodCard`) and the intake drafts view (`drafts`, `draftVersions`). Whether these are wanted is a product decision.
4. **S5 has no route.** Allocation/distribution is built but unreachable by any user (Class B).
5. **`/operations` runtime coverage depends on a populated fixture** — a green `currency-safe-pages` run is *not* runtime proof for it.
6. **`investment_projects.reporting_currency` can only be `'EGP'` today.** Other-currency *facts* still occur inside an EGP project, so the exposure is real; do not infer a project-level defect (or its absence) from the column.
7. **`DistributionCapacity.technical_capacity_bridge_minor_units` mismatches the view's `distributable_cash_minor_units`** — a naming inconsistency to reconcile when S5 gets a route.
8. **Documentation drift is recurrent.** Test/route/migration counts in prose went stale twice during this session alone; the generators catch design docs, not prose.

---

## J. Next Execution Plan

**Immediate (product decisions, no code required):**
1. Decide the fate of the Class-C dropped UI — close-run gates/exceptions, intake drafts — and either build or remove the dead props/locals *deliberately*.
2. Decide whether S5 receives a route, or the readers are marked as an internal API.
3. Run `npm run db:test` and the `r15:admission` check on a Postgres-capable runner; that closes risk #1.

**Then, in order:**
4. Re-grain the two reporting-currency slice views only after confirming the downstream gates consume the per-currency contracts; the per-currency readers already exist to build against.
5. Add runtime coverage for any surface whose fixture is empty (risk #5).
6. Reconcile the `DistributionCapacity` field name when S5 is surfaced (risk #7).

**Standing operating rules for whoever continues:**
- `npm run dev` rewrites `next-env.d.ts` — restore it before committing.
- `route-review --check` **should** fail when a page changes; regenerate the doc, never hand-edit `docs/design/ROUTE_REVIEW.md`.
- Never edit `scripts/ui-preview/fixtures.mjs` to pad a scenario; the fixture test asserts the currency mix that makes cross-currency sums detectable.
- **Do not use `git checkout -- <file>` on a file holding uncommitted work.** It cost this session three repairs, recoverable only because the new test encoded them. Commit before mutating.
- A 4173 response or a directory listing is not app-preview evidence; the sanctioned path is `npm run dev` + the mock at `:54329`.

---

### Appendix: commit history of this recovery

| Commit | Content |
|---|---|
| `5156a51` | base — `main`, PR #178 |
| `0676941` | `recover:` single authoritative state for the currency-safe money contract |
| `3b0bfd3` | `fix:` stop three surfaces inventing a money value the data does not contain |
| `5f0065b` | `docs:` regenerate route review for the repaired surfaces |

Remote `arena/4c002d8d-terranex` = local `5f0065b`. No history was rewritten, no force-push was performed, and no generated file was committed.

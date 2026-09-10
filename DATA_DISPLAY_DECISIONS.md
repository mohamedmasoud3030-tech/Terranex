# Data Display Decisions (Phase 4)

Each dataset gets one pattern chosen from the user's task. Density: finance/review pages are **dense** (desktop-strong); index pages are **comfortable**. No dataset currently exceeds a few hundred rows per project, so **no pagination** is introduced; lists over 50 rows get a "عرض المزيد" client toggle in a later milestone. Sorting is server-defined (newest first) and stated in the section subtitle; no client sorting until a real need appears.

Mobile strategy vocabulary: **PC** = priority columns (others hidden behind row expansion), **HC** = horizontal containment (scroll inside `.table-wrap`, first column sticky), **T2C** = table-to-card list, **SD** = summary + drill-down.

| Page · dataset | Pattern | Why | Hierarchy (first → last) | Sort / filter / search | Selection / bulk | Row actions | Statuses | Mobile strategy | States |
|---|---|---|---|---|---|---|---|---|---|
| Home · integrity signals | **List** (attention list) | sequential scan, few fields, action = open | label → severity badge → subject count → project link | severity desc, then count | none (approvals must be per-subject per UX baseline) | open project integrity | حرج/تحذير/معلومة | same | empty = "لا إشارات مفتوحة" |
| Home · consolidated money | **Stats** (4) | one threshold decision (is cash/payables position known?) gated by FX status | cash → payables → paid → project count | — | — | — | FX banner when incomplete | 2×2 | banner state |
| Home · sector performance | **Table** desktop / **cards** mobile | comparison across sectors (8 numeric cols) | sector → projects → assets → cash → revenue → cost → expense → result | by sector | none | — | — | T2C | empty |
| Home / `/projects` · projects | **Cards** | browse; sector identity; independent link | name → sector+lifecycle badges → currency → reference | newest first; client text filter | none | open | lifecycle (Arabic) | 1 col | empty, no-results |
| `/portfolios` · portfolios | **Cards** | same | name → status → assigned count | newest | none | open | draft/active/archived | 1 col | empty |
| `/portfolios/[id]` · assigned projects | **Table** | compare lifecycle/sector across projects; remove action | project → sector → lifecycle → assigned at → action | assigned desc | none | remove (reason) | lifecycle | PC (project, lifecycle) | empty |
| `/portfolios/[id]` · assignment history, status history | **Timeline** (collapsed) | chronological meaning | date → event → actor/reason | chronological | — | — | — | stacked | empty |
| `/assets` · register | **Table** | compare across stable columns with absence semantics | asset → project → state → cost → valuation → result → registered | registered desc | none | open project | operational state (Arabic) | HC (asset sticky) | empty |
| Project home · KPIs | **Stats** linking to sections | orientation | contributed → cash → result → period | — | — | — | — | 2×2 | — |
| Overview · KPI groups | **Stats** grouped | status at a glance, each links to source | capital → cash/payables → revenue → close | — | — | — | negative flag | 2-across | forbidden |
| Overview · assets | **Table** | short comparison | asset → state → strategy | — | — | — | state | PC | empty |
| Funding · partner positions | **Table** | numeric comparison per participant | participant → commitment → called → contributed → receivable | — | none | — | — | HC | agreement gate |
| Funding · capital calls | **Table** with nested lines as sub-rows | calls compared; lines belong to call | reference → due → status → lines | issued desc | none | — | مُصدر/ملغى | T2C | empty |
| Funding · contributions | **Table** | register | date → investor → call → amount → version | date desc | — | — | — | PC | empty |
| Terms · parties/participants | **Table** | compare | name → type → role | name | — | add as participant | — | PC | empty |
| Operations · property assets | **Cards** with key-value facts | each asset has identity, state, independent actions | name → state → reference → title/possession → acquisition | state changed desc | none | per-asset actions | operational state (Arabic) | 1 col | empty → create profile |
| Operations · phases/milestones | **List** | ordered sequence | seq → name → planned → actual | seq | — | achieve | state | stacked | empty |
| Operations · cost control | **Table** | budget vs committed vs actual | category → budget → committed → actual → variance | — | — | — | variance sign | HC | empty |
| Operations · timeline | **Timeline** | chronology | date → event → state → reason | desc | — | — | — | stacked | empty |
| Costs · obligations | **Table** + row disclosure | owner compares outstanding/aging and acts per row | supplier → description → amount → outstanding → aging/due → status → actions | created desc | none (material approvals per row) | authorize, delete draft, terms/schedule, dispute, retention release, pay | مسودة/معتمد/مسدد/معكوس + aging | T2C (supplier, outstanding, status, actions) | empty, forbidden-by-role copy |
| Costs · metrics | **Stats** (6) | thresholds (overdue, disputed) | total → paid → outstanding → overdue → retention → disputed | — | — | — | overdue negative | 2×3 | — |
| Cash · accounts | **Table** | compare balances | account → currency → balance → last posting | name | — | — | — | PC | empty |
| Cash · payments, statement lines | **Table** | reconciliation comparison | date → amount → account → status | date desc | none | match/approve | reconciled | HC | empty |
| Revenue · dispositions / rentals / results | **Table** | numeric comparison | asset → amount → collected → outstanding → status | date desc | — | recognize/collect (owner, disclosure) | recognized/collected/reversed | T2C | empty |
| Close · periods | **List** | few fields, sequence | dates → status → version | start desc | — | open/close/reopen | مفتوحة/مغلقة | stacked | empty |
| Close · run gates | **Checklist list** | decision = can we close? | gate → result → detail → exception | gate order | — | approve exception | PASS/FAIL/exception/N/A | stacked | — |
| Pilot · readiness | **Stats** | thresholds | imports → rejected → totals match → checkpoints → variances → exceptions | — | — | — | — | 2-across | — |
| Pilot · pending approvals | **List** | work queue | kind → label → since → link | since asc | none | open | — | stacked | empty |
| Pilot · import rows, checkpoints, exceptions, UAT, rehearsals, members | **Table** | audit comparison | id/code → status → amounts → actor | row order | none | per row | status | HC | empty |
| Pilot · staging form rows | **Table of inputs** | data entry grid | mapping → party → account → debit → credit → description | — | — | add/remove row | — | HC inside form (must not widen page) | — |
| Controls · gates | **Checklist list** | readiness | group → gate → status → detail | fixed | — | — | satisfied/pending/not | stacked | — |
| Controls / Pilot · members | **Table** | access review | user → role → status → access → since | — | — | revoke (owner) | — | PC | empty |
| Intake · steps | **Stepper list** | sequence with completion | step → status → open | fixed | — | open step | complete/missing/blocked… (existing badges) | stacked | — |
| Budget · versions / consumption / FAC | **Table** | numeric comparison | version → status → total; line → cap → consumed → remaining | — | — | approve (owner) | status | HC | empty |
| Integrity · signals / exceptions / policies | **Table** | audit comparison | code → severity → count → amount | severity | — | — | severity (Arabic) | T2C | empty |
| Integrity · FX / tax / consolidation | **Key-value / table (collapsed reference)** | reference, not daily work | — | — | — | — | — | stacked | — |
| Governance · risks / decisions | **Table** | compare severity/owner | title → severity → owner → status | opened desc | — | resolve | open/resolved | T2C | empty |
| Procurement · suppliers, PR, PO, receipts, invoices | **Table** + row disclosure | compare references/amounts; approvals per row | reference → supplier → state → quantity/amount → actions | created desc | none | approve, attach evidence, receive, invoice | state | T2C | empty |
| Agriculture · farms/fields/cycles | **Cards** (farm) → **table** (fields, cycles) | farm identity; fields/cycles compared | name → area → status → next action | — | — | per-row | lifecycle | 1 col / PC | empty per section |
| Agriculture · activities, applications, harvest, inventory moves, sales | **Table** | chronological comparison with quantities | date → field/cycle → quantity+unit → actor | date desc | — | — | — | T2C | empty |
| Agriculture · cycle results | **Cards** with key-value | one result per cycle, decision = close-out | crop → cost → revenue → result → open positions | — | — | close-out (owner) | open/closed | 1 col | empty |
| Livestock · sites → herds → cohorts | **Cards** nested | identity + counts + actions | name → count → location → last movement | — | — | movements, split/merge, weight | — | 1 col | empty |
| Livestock · movements, weights, sales | **Table** | quantities compared over time | date → cohort → qty/weight → evidence | date desc | — | approve (owner) | state | T2C | empty |

## Keyboard and screen-reader behaviour (all patterns)

- Tables keep `<th scope="col">`; first column includes the row's primary identifier; row disclosure buttons are real `<button aria-expanded>` (or `<details>` with `<summary>` text naming the row).
- Card lists are `<ul>/<li>` with one link per card covering the card (`.project` already a link); secondary actions inside cards are separate buttons, not nested links.
- Stat tiles use `<dl>` semantics when static and `<a>` when they drill down.
- Status is never colour-only: text label always present (existing `.status` chips comply).
- Tab strips use `nav aria-label` + `aria-current="page"` for route tabs; in-page tabs are anchor links (no JS state) so they work without hydration.

# Terranex Verification Matrix

Use the smallest truthful gate during development and the complete changed-layer gate before delivery.

| Changed surface | Minimum evidence |
| --- | --- |
| Documentation/governance only | Diff restricted to intended docs/governance; referenced paths exist; cross-document consistency check |
| Pure TypeScript/domain helper | Targeted Vitest proof; typecheck; lint |
| React/UI behavior | Targeted component/integration tests; typecheck; lint; build when runtime integration changed; RTL/accessibility/failure states when relevant |
| Next.js server action/route/runtime | Targeted tests; typecheck; lint; build; auth/error-path checks |
| Dependency/framework integration | Official version-specific source evidence; tests; typecheck; lint; build; lockfile review |
| PostgreSQL schema/view/function/RLS | Targeted SQL gate; npm run db:test; migration replay/upgrade path; two-tenant isolation when tenant-owned data is touched |
| Financial posting/command lifecycle | Database gate plus atomicity, idempotency, reversal/repost, concurrency, period-lock, and audit evidence as applicable |
| Auth/authorization/storage/security boundary | Negative authorization tests; tenant isolation; secret/privilege review; build/runtime tests as applicable |
| Money/currency/result reporting | Explicit currency grain; no floating point; negative controls for cross-currency or qualification defects when relevant |

Repository-wide tests are not a substitute for a targeted regression proof.

If the environment cannot run a required canonical gate, report it as unresolved and rely on the designated CI gate. Never simulate a pass.

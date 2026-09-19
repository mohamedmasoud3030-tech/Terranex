# Terranex Agent Skills Gap Analysis

## Baseline

At the evaluated repository state, no SKILL.md files existed in Terranex.

The current repository stack is:
- Next.js 16 App Router;
- React 19;
- TypeScript 5.8;
- Supabase JS/SSR with Supabase Auth, PostgreSQL, RLS, and private Storage;
- Vitest;
- Zod.

The canonical architecture is a single deployable application, not an Nx monorepo or NestJS service architecture.

Therefore the correct move is not to install the highest-ranked generic skills wholesale. It is to build a small Terranex skill layer around the repository that actually exists.

## Candidate analysis

| Candidate/source idea | Decision | Terranex destination | Reason |
| --- | --- | --- | --- |
| Source-driven development | MERGE | terranex-implementation | Must be a hard implementation gate for volatile framework behavior; standalone duplication is unnecessary |
| Test-driven development / Prove-It | MERGE | terranex-implementation | Bug reproduction and regression proof belong inside implementation workflow |
| GitHub implementation planning | MODIFY | terranex-implementation-planning | Strong deterministic handoff pattern, adapted to Terranex authority, gates, and no speculative scaffolding |
| Anthropic architecture + system design | MERGE | terranex-architecture-decision | One ADR/system-design workflow avoids overlapping triggers |
| Trail of Bits workflow-skill design | APPLY AS STANDARD | docs/agent-os/SKILL_DESIGN_STANDARD.md | Meta-guidance should shape every skill rather than become a routinely activated project skill |
| EveryInc multi-persona code review | MODIFY | terranex-code-review | Keep risk-selected lenses, deduplication, severity/confidence, and strict review/fix separation |
| OpenAI security best practices | MERGE | terranex-implementation + terranex-code-review | Secure defaults and security review should be embedded where code is written/reviewed rather than duplicated |
| OpenAI security threat model | KEEP / MODIFY | terranex-threat-model | Threat modeling is a distinct artifact and especially important for tenant isolation and privileged boundaries |
| Supabase PostgreSQL best practices | MODIFY | terranex-database | Keep PostgreSQL/RLS/schema/locking/performance guidance and adapt it to Terranex's actual RLS/auth model |
| Official Nx skills | DO NOT INSTALL NOW | none | Nx is not in the current repository and AGENTS.md explicitly defines a non-monorepo architecture |
| ECC NestJS patterns | DO NOT INSTALL NOW | none | NestJS is not in the current repository; installing it would create false triggers and architectural drift |

## Result

Six project skills are sufficient now:
1. architecture decision;
2. implementation planning;
3. implementation;
4. code review;
5. database;
6. threat model.

Skill-authoring guidance remains a repository design standard instead of a seventh runtime skill.

## Re-evaluation trigger

Re-run this gap analysis when:
- AGENTS.md changes the target architecture;
- a new framework becomes an actual committed dependency;
- Terranex introduces a new bounded platform concern not covered by the six trigger domains;
- a project skill becomes too broad and produces repeated false activations.

Do not pre-install Nx, NestJS, Drizzle, Better Auth, or any other stack-specific skill based on a possible future architecture.

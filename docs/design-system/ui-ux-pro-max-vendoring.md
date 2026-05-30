# UI/UX Pro Max Source Manifests

## Purpose

Terranex uses UI/UX Pro Max as a development-time design intelligence library. It is not runtime React code, not a product feature, and not a dependency that should be imported by the application.

This setup gives future Codex UI tasks a documented manifest-only reference point before changing Terranex UI code.

This is not a full vendored copy of upstream UI/UX Pro Max source content.

## Upstream Source Found

The upstream source was identified from the Terranex submodule declaration and public repository metadata:

- `.gitmodules` declares `external/skills/ui-ux-pro-max-skill`.
- The upstream URL is `https://github.com/nextlevelbuilder/ui-ux-pro-max-skill.git`.
- The expected upstream internal skill folders live under `.claude/skills/` in that repository.
- During setup, the local submodule path existed but was not initialized with files.
- Attempts to fetch the submodule/archive from GitHub and the npm installer were blocked by `403` responses in this environment.

## Current Manifest-Only Location

The current internal Terranex manifest location is:

`.ai/vendor/ui-ux-pro-max/upstream/`

The required upstream folder contracts are represented at:

- `.ai/vendor/ui-ux-pro-max/upstream/.claude/skills/ui-ux-pro-max/`
- `.ai/vendor/ui-ux-pro-max/upstream/.claude/skills/ui-styling/`
- `.ai/vendor/ui-ux-pro-max/upstream/.claude/skills/design-system/`
- `.ai/vendor/ui-ux-pro-max/upstream/.claude/skills/brand/`
- `.ai/vendor/ui-ux-pro-max/upstream/.claude/skills/design/`

Each folder currently contains only a `SOURCE.md` file with its original upstream URL, expected local submodule path, purpose, Terranex usage notes, and runtime boundary.

The actual upstream `SKILL.md` files, scripts, data files, examples, references, templates, generated assets, and other guidance files are not present in this PR because upstream fetches were blocked by `403`.

Future UI tasks must not treat this folder as complete UI/UX Pro Max source content unless a later refresh adds the real upstream files.

## Terranex Adapter Skill

Terranex-specific UI work must use this adapter before changing UI runtime files:

`.ai/skills/terranex-ui-ux-pro-max/SKILL.md`

The adapter combines these manifest-only upstream source contracts with Terranex-specific constraints:

- Arabic-first.
- RTL-first.
- Mobile-first.
- React + Tailwind + Radix.
- Financial operating system style.
- No fake/demo data.
- EGP / `ج.م` currency expectations.
- localStorage currently only.
- Preserve routes, finance behavior, dashboard direction, and product model.

## How Codex Should Use It

For any future UI task, Codex should first read:

1. `docs/design-system/MASTER.md`
2. `docs/design-system/ui-ux-pro-max-vendoring.md`
3. `.ai/skills/terranex-ui-ux-pro-max/SKILL.md`
4. Relevant `SOURCE.md` manifests under `.ai/vendor/ui-ux-pro-max/upstream/.claude/skills/`

Then Codex should state which manifests were consulted and apply the adapter's mobile, RTL, accessibility, dashboard, KPI, sector-card, empty-state, and financial table/list gates before implementation.

If actual upstream source files are added later, Codex should consult those files in addition to these Terranex-specific docs.

## Runtime Import Ban

Never import these files from app runtime code:

- `.ai/vendor/ui-ux-pro-max/**`
- `.ai/skills/**`
- `external/skills/ui-ux-pro-max-skill/**`

These folders are for agents and design review only. They must not be referenced from `src/**`, route code, React components, build-time app imports, finance logic, storage code, or package dependencies.

## Future Maintenance

When the upstream submodule or archive is available, refresh `.ai/vendor/ui-ux-pro-max/upstream/` by replacing or supplementing these manifests with the actual selected upstream source files while keeping Terranex customization separate in `.ai/skills/terranex-ui-ux-pro-max/`.

Do not edit copied upstream source content once it exists unless path adjustments are necessary. Project-specific constraints belong in the Terranex adapter skill and Terranex design-system docs.

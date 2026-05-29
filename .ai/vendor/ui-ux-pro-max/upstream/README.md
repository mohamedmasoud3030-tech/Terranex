# UI/UX Pro Max Upstream Source Manifests

This directory is Terranex's temporary, manifest-only source-contract location for the selected upstream UI/UX Pro Max skill folders.

It is not a full vendored copy of upstream source content. It currently contains only this `README.md` plus one `SOURCE.md` manifest per selected upstream folder.

## Upstream source identified

- Repository: `https://github.com/nextlevelbuilder/ui-ux-pro-max-skill`
- Terranex submodule declaration: `external/skills/ui-ux-pro-max-skill`
- Submodule URL: `https://github.com/nextlevelbuilder/ui-ux-pro-max-skill.git`
- Expected upstream commit from `.gitmodules`/submodule status: `b7e3af80f6e331f6fb456667b82b12cade7c9d35`
- Local submodule state during setup: path existed but upstream files were not initialized.
- Fetch result during setup: GitHub and npm downloads returned `403`, so actual upstream files were not fetched.

## Current state

This folder currently records upstream source paths, expected local submodule paths, purpose, Terranex usage notes, and runtime boundaries only.

It does not contain upstream `SKILL.md` files, scripts, data files, examples, references, templates, generated assets, or other actual UI/UX Pro Max guidance content.

Future UI tasks cannot rely on this directory as the complete UI/UX Pro Max source. They may use these manifests only to understand the intended upstream folders and runtime boundaries until the real upstream content is available.

## Manifest-only folder contracts

The required upstream folders are represented under their original internal paths:

- `.claude/skills/ui-ux-pro-max/`
- `.claude/skills/ui-styling/`
- `.claude/skills/design-system/`
- `.claude/skills/brand/`
- `.claude/skills/design/`

Each folder includes a `SOURCE.md` file that records the original upstream path, purpose, and Terranex usage notes.

## Future refresh requirement

If upstream access becomes available, refresh this directory by replacing or supplementing these manifests with the actual selected upstream files from the matching UI/UX Pro Max folders. Keep upstream source content separate from Terranex-specific customization in `.ai/skills/terranex-ui-ux-pro-max/`.

## Runtime boundary

These files are design-intelligence references only. They must never be imported from React runtime code, bundled into the application, used as a route dependency, or treated as product data.

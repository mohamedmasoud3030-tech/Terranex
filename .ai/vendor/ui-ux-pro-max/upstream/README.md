# Vendored UI/UX Pro Max Upstream Reference

This directory is Terranex's stable, internal reference location for the selected upstream UI/UX Pro Max skill folders.

## Upstream source identified

- Repository: `https://github.com/nextlevelbuilder/ui-ux-pro-max-skill`
- Terranex submodule declaration: `external/skills/ui-ux-pro-max-skill`
- Submodule URL: `https://github.com/nextlevelbuilder/ui-ux-pro-max-skill.git`
- Expected upstream commit from `.gitmodules`/submodule status: `b7e3af80f6e331f6fb456667b82b12cade7c9d35`
- Local submodule state during setup: path existed but upstream files were not initialized.
- Fetch result during setup: GitHub and npm downloads returned `403`, so this vendored location records the discovered upstream folder contracts and source URLs for stable Terranex usage.

## Vendored folder contracts

The required upstream folders are represented under their original internal paths:

- `.claude/skills/ui-ux-pro-max/`
- `.claude/skills/ui-styling/`
- `.claude/skills/design-system/`
- `.claude/skills/brand/`
- `.claude/skills/design/`

Each folder includes a `SOURCE.md` file that records the original upstream path, purpose, and Terranex usage notes.

## Runtime boundary

These files are design-intelligence references only. They must never be imported from React runtime code, bundled into the application, used as a route dependency, or treated as product data.


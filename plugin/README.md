# Terranex Investment OS Plugin Scaffold

This folder contains the structured Terranex agent and skill layer.

## Purpose

The plugin layer gives Terranex reusable working patterns for product planning, domain modeling, financial design, document analysis, repository understanding, pipeline work, and UI/UX planning.

## Layout

```text
plugin/
├── manifest.json
├── README.md
├── agents/
│   └── *.md
└── skills/
    └── skill-name/
        ├── SKILL.md
        └── references/
```

## Relationship to app code

This folder is not the application runtime. It is the project intelligence layer used to guide, audit, and organize future implementation work.

## Boundary

Terranex is independent from Rentrix and all other repositories. Any reusable pattern should be adapted to Terranex terms before being used.

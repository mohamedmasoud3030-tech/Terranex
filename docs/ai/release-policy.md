# Terranex Release Policy

Before merge:

- Keep the change inside the approved Terranex stage.
- Preserve traceability, deletion guards, audit history, and local persistence safety.
- Keep migrations versioned and backward-aware.
- Keep production runtime free from automatic demo records.
- Check Arabic RTL and responsive behavior on affected screens.
- Run `npm run typecheck`, `npm run lint`, `npm run test`, and `npm run build`.
- Report changed files, domain impact, migration impact, results, blockers, and commit SHA.

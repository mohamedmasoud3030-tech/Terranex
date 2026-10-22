# Legacy Freeze Record

**Frozen:** 2026-08-10

**Repository:** `mohamedmasoud3030-tech/Terranex`

**Legacy branch:** `legacy/pre-greenfield-20260810`
**Frozen commit:** `1d4e7edc836ca6e245a8a629be5502b3f38d5cbf`

The branch above preserves the complete former Terranex application, migrations, integrations, tests, CI, and historical documentation. It is recoverable reference, not a product baseline.

Rules:

- Do not branch new product work from the legacy branch.
- Do not port legacy business logic into Greenfield.
- Reuse of a generic technical fragment requires a separate written compatibility assessment against the eight Greenfield documents.
- The former deployment and production data are not modified by the Greenfield reset.

The Greenfield working branch is `greenfield/foundation`.

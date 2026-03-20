# Admin App Instructions

## Scope
These instructions apply specifically to the Flutter admin app.

## Product Focus
- Web-first admin console for operational workflows.
- Optimize for desktop usage, dense information, and fast management.
- Do not design this like a consumer storefront.

## Architecture
- Prefer structured modules for disputes, listings, orders, customers, settings, and audit logs.
- Keep data operations backend-driven and role-aware.
- Avoid placeholder panels when a real operational workflow can be implemented.

## Backend Rules
- Admin actions must respect server-authoritative ownership.
- Disputed items cannot be listed, sold, or transferred.
- Frozen or stolen items cannot be claimed, listed, or transferred.
- Freeze/unfreeze and lost/stolen actions must use backend-backed operations.
- Audit-sensitive actions should create or surface audit records.

## UX
- Use tables, filters, drawers, modals, and confirmation flows where appropriate.
- Prioritize clarity and speed over decorative UI.
- Keep the same premium black/gold/off-white tone as the brand.
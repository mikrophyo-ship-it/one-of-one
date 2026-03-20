# One of One Architecture

See `docs/architecture.md` for the full architecture document.

## Snapshot
- Flutter customer app for mobile-first collecting, claiming, vault, and resale.
- Flutter admin app for web-first operations, minting, inventory, disputes, and settings.
- Shared Dart domain, data, service, UI, and utility packages.
- Supabase schema with server-authoritative ownership, RLS, ledger accounting, public authenticity projection, and state-transition enforcement.
- V2-ready hooks for NFC and Bluetooth transfer verification without implementing them in V1.

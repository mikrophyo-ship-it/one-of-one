# One of One Architecture

## Monorepo shape
- `apps/customer_app`: mobile-first Flutter customer experience for authentication, discovery, authenticity scan, claiming, vault, resale, disputes, and profile.
- `apps/admin_app`: Flutter web-first operations console for artists, artworks, minting, inventory, disputes, audits, and settings.
- `packages/domain`: pure Dart domain entities and business rules, including item state transitions and resale fee logic.
- `packages/data`: repository contracts and demo data for local development without a live backend.
- `packages/services`: payment abstraction and backend-facing payload/service boundaries.
- `packages/core_ui`: shared black, gold, and ivory design language.
- `packages/utils`: validation and formatting helpers.
- `supabase/`: SQL migrations and seed data for schema, RLS, server-authoritative workflow functions, and public authenticity queries.

## Architecture choices
- Presentation, application, domain, and data concerns are separated in intent, but the current apps still need further modularization because much of the app logic lives in single large files.
- Critical ownership and resale rules live in `packages/domain` and are mirrored by SQL functions in Supabase so the client never becomes the source of truth.
- Payment handling is abstracted behind `PaymentProvider`; V1 uses a mock provider but the interface is stable for Stripe/Adyen/etc. later.
- Public authenticity and private ownership claim are split: QR opens a public route, while hidden claim code validation happens through a protected server-side function.
- Unique garments are modeled as `unique_items`, not generic stock, so provenance, state, and resale history attach to the collectible unit itself.

## Backend design
- `unique_items.current_owner_user_id` is only authoritative when paired with an open `ownership_records` row.
- `handle_auth_user_created` mirrors Auth signups into `public.users` automatically.
- `upsert_my_profile`, `claim_item_ownership`, `create_resale_listing`, `create_resale_order`, `record_resale_payment_and_transfer`, `open_dispute`, and `admin_flag_item_status` are the main RPC entry points for V1.
- `public_authenticity_items` and `get_public_authenticity_by_qr_token` provide a privacy-safe authenticity surface.
- `public_marketplace_listings` provides a sanitized public shopping surface without exposing hidden claim data or owner identity.
- Disputed, stolen, and frozen states are blocked centrally before claim, listing, or transfer can proceed.
- Ledger tables split seller payout, artist royalty, and platform fee so resale economics stay auditable.

## Storage buckets
- `public-authenticity`: public QR-facing media and editorial item imagery.
- `artist-proof-private`: draft sketches, process media, and signed provenance assets.
- `garment-editorial`: polished release imagery.
- `claim-code-packaging-private`: package inserts and claim-code artifacts.

## V2 hooks intentionally prepared
- `ownership_transfers.v2_transfer_channel` preserves room for NFC/Bluetooth verification later without changing core ownership authority.
- Routing and app structure leave space for dedicated public authenticity web routing.
- Payment service boundary and admin settings are ready for a real provider and more advanced payout orchestration.

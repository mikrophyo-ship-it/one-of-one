# One of One Architecture

## Monorepo shape
- `apps/customer_app`: mobile-first Flutter customer experience for authentication, discovery, authenticity scan, claiming, vault, resale, disputes, and profile.
- `apps/admin_app`: Flutter web-first operations console for customers, orders, listing moderation, disputes, audits, freeze controls, and settings.
- `packages/domain`: pure Dart domain entities and business rules, including item state transitions, admin operational read models, and resale fee logic.
- `packages/data`: repository contracts plus Supabase-backed marketplace and admin repositories for live reads and RPC-driven actions.
- `packages/services`: payment abstraction and backend-facing workflow services for customer and admin surfaces.
- `packages/core_ui`: shared black, gold, and ivory design language.
- `packages/utils`: validation and formatting helpers.
- `supabase/`: SQL migrations and seed data for schema, RLS, server-authoritative workflow functions, public authenticity queries, and admin operational views.

## Architecture choices
- Presentation, application, domain, and data concerns are separated in intent, but both apps still have room for further modularization after V1.
- Critical ownership, dispute, moderation, and resale rules live in `packages/domain` and are mirrored by SQL functions in Supabase so the client never becomes the source of truth.
- Payment handling is abstracted behind `PaymentProvider`; V1 uses a mock provider but the interface is stable for Stripe/Adyen/etc. later.
- Public authenticity and private ownership claim are split: QR opens a public route, while hidden claim code validation happens through a protected server-side function.
- The customer app prefers the Supabase repository and refreshes catalog, owned collectibles, and ownership history from backend views and RPCs after claim, resale, checkout, and dispute actions.
- The admin app now prefers a Supabase-backed admin repository and reads dense operational queues rather than embedding moderation logic in widgets.
- Unique garments are modeled as `unique_items`, not generic stock, so provenance, state, and resale history attach to the collectible unit itself.

## Backend design
- `unique_items.current_owner_user_id` is only authoritative when paired with an open `ownership_records` row.
- `handle_auth_user_created` mirrors Auth signups into `public.users` automatically.
- `upsert_my_profile`, `claim_item_ownership`, `create_resale_listing`, `create_resale_order`, `record_resale_payment_and_transfer`, `open_dispute`, `admin_moderate_listing`, `admin_update_dispute_status`, `admin_update_platform_settings`, and `admin_flag_item_status` are the main RPC entry points for V1.
- `public_authenticity_items` and `get_public_authenticity_by_qr_token` provide a privacy-safe authenticity surface.
- `public_marketplace_listings` and `public_collectible_catalog` provide sanitized public shopping surfaces without exposing hidden claim data or owner identity.
- `get_my_collectibles()` and `get_my_item_history(item_id)` provide owner-safe authenticated reads for vault and provenance refresh.
- `admin_dashboard_overview`, `admin_customer_overview`, `admin_listing_queue`, `admin_dispute_queue`, `admin_order_queue`, and `admin_audit_feed` provide the web admin console with operational read models behind admin-capable RLS.
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

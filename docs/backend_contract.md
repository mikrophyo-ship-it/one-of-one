# One of One Backend Contract

## Trust boundary
Supabase is the source of truth for ownership, listing eligibility, dispute blocking, payment capture, transfer accounting, and admin moderation. Client apps should not mutate these states locally and then assume success.

## Public read surface
Use these for anonymous or broad customer-facing reads:
- `public.public_authenticity_items`
- `public.get_public_authenticity_by_qr_token(text)`
- `public.public_marketplace_listings`
- `public.public_collectible_catalog`

These surfaces intentionally avoid exposing:
- hidden claim codes
- claim code hashes
- private owner identity
- seller contact details
- private payment or address data

## Authenticated customer RPCs
After a real Auth signup, call:
- `public.upsert_my_profile(display_name, username, avatar_url)`

Owner-safe authenticated reads:
- `public.get_my_collectibles()`
- `public.get_my_item_history(item_id)`

For ownership and resale lifecycle:
- `public.claim_item_ownership(item_id, claim_code)`
- `public.claim_item_ownership_by_qr_token(public_qr_token, claim_code)`
- `public.create_resale_listing(item_id, price_cents)`
- `public.create_resale_order(listing_id)`
- `public.record_resale_payment_and_transfer(order_id, provider, provider_reference, amount_cents)`
- `public.open_dispute(item_id, reason, details, freeze_item)`

## Authenticated admin RPCs
Mutation RPCs:
- `public.admin_flag_item_status(item_id, target_state, note)`
- `public.admin_set_user_role(user_id, role)`
- `public.admin_moderate_listing(listing_id, action, note)`
- `public.admin_update_dispute_status(dispute_id, status, note, release_item, release_target_state)`
- `public.admin_update_platform_settings(platform_fee_bps, default_royalty_bps, marketplace_rules, brand_settings)`

Read RPCs:
- `public.get_admin_dashboard_overview()`
- `public.get_admin_customer_overview()`
- `public.get_admin_listing_queue()`
- `public.get_admin_dispute_queue()`
- `public.get_admin_order_queue()`
- `public.get_admin_audit_feed()`

These RPCs enforce admin-capable role checks before returning operational data.

## Lifecycle
1. A real user signs up through Supabase Auth.
2. Auth trigger `handle_auth_user_created` creates the corresponding `public.users` row.
3. The app calls `upsert_my_profile(...)` to create the user profile.
4. A QR scan resolves privacy-safe authenticity details through `get_public_authenticity_by_qr_token(...)`.
5. The customer app refreshes public catalog data from `public_collectible_catalog` and the authenticated collector state from `get_my_collectibles()`.
6. A buyer with a hidden claim code calls `claim_item_ownership_by_qr_token(...)` or `claim_item_ownership(...)`.
This marks the claim code as consumed, records the owner, and creates the open ownership record.
7. The current owner calls `create_resale_listing(...)`.
This is allowed only when the user is the recorded current owner and the item is in an eligible state.
8. Another user calls `create_resale_order(listing_id)`.
This locks the listing into `sale_pending` and creates the resale order and order_item rows.
9. After payment success, the backend calls `record_resale_payment_and_transfer(...)`.
This records the captured payment, marks the order paid, finalizes the ownership transfer, and writes payout, royalty, and platform fee ledgers.
10. If a customer reports a problem, `open_dispute(...)` moves the item into `disputed` or `frozen` and blocks listing and transfer.
11. Admin can moderate listings through `admin_moderate_listing(...)`, resolve or reject disputes through `admin_update_dispute_status(...)`, and force item restrictions like `stolen_flagged`, `frozen`, or safe release states through `admin_flag_item_status(...)`.
12. Admin settings edits persist through `admin_update_platform_settings(...)`, and admin queue reads are returned only through the admin-checked read RPCs.

## Local development flow
1. Apply migrations and `supabase/seed/seed.sql`.
2. Create local users through Supabase Auth UI or app sign-up.
3. Sign in as each user and call `upsert_my_profile(...)`.
4. Promote one account to admin through a bootstrap admin path, then use `admin_set_user_role(...)` for later role changes.
5. Use the seeded `sold_unclaimed` items and their packaged hidden codes for claim testing.
6. Drive authenticity lookup, claim, listing, order, payment, dispute, moderation, and settings flows through RPCs and views rather than direct table writes.

## Seed notes
`supabase/seed/seed.sql` seeds collectible catalog and authenticity data only. It intentionally does not insert into `auth.users`.

## Current app integration
- The customer app now uses real Supabase Auth session state plus Supabase-backed reads and RPCs through its repository and service architecture.
- It resolves QR and public authenticity through `get_public_authenticity_by_qr_token(...)` and keeps claim codes out of public authenticity views.
- The admin app now uses Supabase-backed operational reads plus admin RPCs for disputes, listing moderation, customer roles, audit viewing, freeze controls, and persisted settings.

## Remaining app integration work
- Replace mock payment capture with a real payment provider when V1 is ready for live checkout.
- Add deployed password-reset redirect URLs and deep-link handling for production mobile reset flows.
- Add camera-based QR scanning and external deep-link entry for the public authenticity experience.

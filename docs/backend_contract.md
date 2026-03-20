# One of One Backend Contract

## Trust boundary
Supabase is the source of truth for ownership, listing eligibility, dispute blocking, payment capture, and transfer accounting. Client apps should not mutate these states locally and then assume success.

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
- `public.create_resale_listing(item_id, price_cents)`
- `public.create_resale_order(listing_id)`
- `public.record_resale_payment_and_transfer(order_id, provider, provider_reference, amount_cents)`
- `public.open_dispute(item_id, reason, details, freeze_item)`

## Authenticated admin RPCs
- `public.admin_flag_item_status(item_id, target_state, note)`
- `public.admin_set_user_role(user_id, role)`

## Lifecycle
1. A real user signs up through Supabase Auth.
2. Auth trigger `handle_auth_user_created` creates the corresponding `public.users` row.
3. The app calls `upsert_my_profile(...)` to create the user profile.
4. The customer app refreshes public catalog data from `public_collectible_catalog` and the authenticated collector state from `get_my_collectibles()`.
5. A buyer with a hidden claim code calls `claim_item_ownership(...)`.
This marks the claim code as consumed, records the owner, and creates the open ownership record.
6. The current owner calls `create_resale_listing(...)`.
This is allowed only when the user is the recorded current owner and the item is in an eligible state.
7. Another user calls `create_resale_order(listing_id)`.
This locks the listing into `sale_pending` and creates the resale order/order_item rows.
8. After payment success, the backend calls `record_resale_payment_and_transfer(...)`.
This records the captured payment, marks the order paid, finalizes the ownership transfer, and writes payout, royalty, and platform fee ledgers.
9. If a customer reports a problem, `open_dispute(...)` moves the item into `disputed` or `frozen` and blocks listing/transfer.
10. Owned-item history is refreshed through `get_my_item_history(item_id)`.
11. Admin can force states like `stolen_flagged`, `frozen`, `disputed`, `claimed`, or `archived` through `admin_flag_item_status(...)`.

## Local development flow
1. Apply migrations and `supabase/seed/seed.sql`.
2. Create local users through Supabase Auth UI or app sign-up.
3. Sign in as each user and call `upsert_my_profile(...)`.
4. Promote one account to admin through a bootstrap admin path, then use `admin_set_user_role(...)` for later role changes.
5. Use the seeded `sold_unclaimed` items and their packaged hidden codes for claim testing.
6. Drive listing, order, payment, and dispute flows through RPCs rather than direct table writes.

## Seed notes
`supabase/seed/seed.sql` seeds collectible catalog and authenticity data only. It intentionally does not insert into `auth.users`.

## Current customer app integration
- The customer app now uses real Supabase Auth session state plus Supabase-backed reads and RPCs through its repository/service architecture.
- It keeps hidden claim codes out of public pages and only sends claim codes to the claim RPC.
- Critical item state is refreshed from Supabase after claim, resale listing, checkout, and dispute actions.

## Remaining app integration work
- Replace mock payment capture with a real payment provider when V1 is ready for live checkout.
- Add deployed password-reset redirect URLs and deep-link handling for production mobile reset flows.
- Extend admin UI to call the matching admin RPCs and operational reads.


# One of One

One of One is a premium collectible fashion marketplace for original human-made artwork garments with platform-authoritative ownership, authenticity verification, and controlled on-platform resale.

## What is included in V1
- Flutter customer app for authentication, discovery, item detail, QR authenticity lookup, ownership claim, vault, resale, disputes, and profile views.
- Flutter admin app for operational overview, customers, orders, listing moderation, disputes, audit review, and persisted marketplace settings.
- Shared Dart packages for domain rules, repository contracts, services, formatting, and design system.
- Supabase schema, RLS posture, server-side ownership and resale functions, admin moderation functions, customer-facing catalog/history contract views and RPCs, and safer catalog-only seed data.
- Automated offline verification for fee calculation, claim validation, resale eligibility, dispute and freeze blocking, transfer gating, and demo repository behavior.

## Repository structure
- `apps/customer_app`
- `apps/admin_app`
- `packages/core_ui`
- `packages/domain`
- `packages/data`
- `packages/services`
- `packages/utils`
- `supabase/migrations`
- `supabase/seed`
- `docs/architecture.md`
- `docs/backend_contract.md`
- `docs/roadmap.md`

## Local setup
1. Install Flutter and Dart 3.10+.
2. Copy `.env.example` to `.env` and fill in your Supabase values.
3. Run `dart pub get` from the workspace root or per package/app.
4. Apply `supabase/migrations/0001_init.sql`, `supabase/migrations/0002_marketplace_hardening.sql`, `supabase/migrations/0003_backend_contract_completion.sql`, `supabase/migrations/0004_customer_read_contract.sql`, `supabase/migrations/0005_qr_claim_contract.sql`, `supabase/migrations/0006_admin_operations_contract.sql`, `supabase/migrations/0007_admin_read_gateways.sql`, `supabase/migrations/0008_fix_admin_role_rls_recursion.sql`, `supabase/migrations/0009_v2_commercial_maturity.sql`, `supabase/migrations/0010_stripe_checkout_reconciliation.sql`, `supabase/migrations/0011_payment_reconciliation_refs.sql`, `supabase/migrations/0012_admin_artwork_concept_note_fix.sql`, `supabase/migrations/0013_admin_garment_product_directory.sql`, `supabase/migrations/0014_inventory_qr_claim_generation.sql`, `supabase/migrations/0015_admin_inventory_publish_workflow.sql`, `supabase/migrations/0016_claim_digest_extension_fix.sql`, `supabase/migrations/0017_item_media_and_comments.sql`, and `supabase/seed/seed.sql` to your Supabase project.
5. Create real local-dev users through Supabase Auth, not through SQL inserts into `auth.users`.
6. After sign-in, call `public.upsert_my_profile(display_name, username, avatar_url)` for each account.
7. Grant an admin role with `public.admin_set_user_role(user_id, role)` from an existing admin account or dashboard bootstrap step.
8. Deploy the Supabase edge functions in `supabase/functions/stripe-create-checkout-session` and `supabase/functions/stripe-webhook`, then configure Stripe secret and webhook environment variables on the function runtime.
9. Run `flutter run -d chrome --project-dir apps\admin_app --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` for the admin console.
10. Run `flutter run --project-dir apps\customer_app --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=CHECKOUT_SUCCESS_URL=... --dart-define=CHECKOUT_CANCEL_URL=...` for the mobile-first customer app.

## Verification commands
- `dart packages\domain\test\marketplace_rules_test.dart`
- `dart packages\data\test\demo_catalog_test.dart`
- `flutter test --project-dir apps\customer_app test\smoke_test.dart`
- `flutter test --project-dir apps\admin_app test\smoke_test.dart`
- `flutter analyze --project-dir apps\customer_app`
- `flutter analyze --project-dir apps\admin_app`

## Backend contract docs
- See `docs/backend_contract.md` for the lifecycle, RPCs, views, and local-dev flow.
- See `docs/payment_configuration.md` for local, staging, and production Stripe setup.
- See `docs/roadmap.md` for planned future scope including artist accounts and portal direction.
- See `scripts/stripe/stripe_test_mode_commands.ps1` for a quick Stripe CLI helper.

## Tradeoffs
- V1 keeps app-side state management simple with `ChangeNotifier`-style local orchestration to reduce ceremony while the business rules stay centralized in shared domain and backend layers.
- QR rendering and lookup are wired to a real backend contract without binding the codebase to a specific camera-scanner plugin yet.
- Stripe-hosted checkout and webhook reconciliation are wired for the production-safe V2 payment path, but live deployment still depends on environment-specific Stripe secrets and hosted return URLs.
- The admin console is backend-driven for disputes, listing moderation, customer roles, audit review, freeze controls, and settings persistence, but still needs broader auth hardening and richer operational filtering over time.
- Newly created inventory now needs the admin publish workflow: create the linked authenticity record, then create or publish the listing from the admin catalog so the item becomes visible and buyable in the customer app without manual SQL.
- Editorial item imagery and customer comments now depend on `0017_item_media_and_comments.sql`, which adds public collectible media attachment and authenticated comment RPCs without exposing hidden claim data.

## Deferred to V2
- NFC and Bluetooth transfer verification
- Live auction bidding
- Buyer/seller chat
- Social comments
- Advanced recommendation engine
- Full real payment gateway integration
- Deep localization beyond architecture readiness

## Notes
- Ownership, listing, dispute, moderation, payment capture, and transfer authority are enforced in Supabase RPCs rather than trusted client state.
- The current repository still needs full Flutter platform scaffolding and full analyzer or widget-test verification in an unrestricted local environment if your sandbox blocks Flutter subprocesses.



## Admin Claim Workflow
Apply `supabase/migrations/0018_admin_claim_operations.sql` before using admin-side hidden claim code reveal or printable claim packets.
This migration adds:
- admin-only secure claim material storage for newly created inventory
- separate audited semantics for one-time reveal vs one-time packet generation
- required operator reason text for both sensitive actions

# One of One

One of One is a premium collectible fashion marketplace for original human-made artwork garments with platform-authoritative ownership, authenticity verification, and controlled on-platform resale.

## What is included in V1
- Flutter customer app for authentication, discovery, item detail, scan demo, ownership claim, vault, resale, and profile views.
- Flutter admin app for overview, artist and artwork management, minting, inventory review, and marketplace settings.
- Shared Dart packages for domain rules, repository contracts, services, formatting, and design system.
- Supabase schema, RLS posture, server-side ownership and resale functions, customer-facing catalog/history contract views and RPCs, dispute controls, and safer catalog-only seed data.
- Pure Dart offline verification for fee calculation, ownership claim validation, dispute/frozen blocking, and state transitions.

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

## Local setup
1. Install Flutter and Dart 3.10+.
2. Copy `.env.example` to `.env` and fill in your Supabase values.
3. Run `dart pub get` from the workspace root or per package/app.
4. Apply `supabase/migrations/0001_init.sql`, `supabase/migrations/0002_marketplace_hardening.sql`, `supabase/migrations/0003_backend_contract_completion.sql`, `supabase/migrations/0004_customer_read_contract.sql`, and `supabase/seed/seed.sql` to your Supabase project.
5. Create real local-dev users through Supabase Auth, not through SQL inserts into `auth.users`.
6. After sign-in, call `public.upsert_my_profile(display_name, username, avatar_url)` for each account.
7. Grant an admin role with `public.admin_set_user_role(user_id, role)` from an existing admin account or dashboard bootstrap step.
8. Run `flutter run -d chrome` from `apps/admin_app` for the admin console.
9. Run `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` from `apps/customer_app` for the mobile-first customer app.

## Useful commands
- `dart packages\domain\test\marketplace_rules_test.dart`
- `dart analyze`
- `flutter run -d chrome --project-dir apps\admin_app`
- `flutter run --project-dir apps\customer_app --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`

## Backend contract docs
- See `docs/backend_contract.md` for the lifecycle, RPCs, views, and local-dev flow.

## Tradeoffs
- V1 keeps app-side state management simple with `ChangeNotifier` to reduce ceremony while the business rules stay centralized in shared domain and backend layers.
- QR rendering/scanning is demonstrated as a product flow and public-route contract without binding the codebase to a specific scanner plugin yet.
- Mock payment capture is still used in the customer app while the backend ownership and ledger path is now real.
- The app now targets a real Supabase repository, but full auth-screen UX and production payment integration still need another pass.

## Deferred to V2
- NFC and Bluetooth transfer verification
- Live auction bidding
- Buyer/seller chat
- Social comments
- Advanced recommendation engine
- Full real payment gateway integration
- Deep localization beyond architecture readiness

## Notes
- Ownership, listing, dispute, payment capture, and transfer authority are enforced in Supabase RPCs rather than trusted client state.
- The current repository still needs full Flutter platform scaffolding and broader analyzer/test verification in an unrestricted environment.

# Customer App Instructions

## Scope
These instructions apply specifically to the Flutter customer app.

## Product Focus
- Mobile-first experience for iOS and Android.
- Premium, minimal, editorial luxury feel.
- This is a collectible ownership app, not a generic shopping app.

## Architecture
- Keep business logic out of widgets.
- Use services/repositories/use-cases for claim, resale, dispute, and profile actions.
- Do not keep ownership, resale, or dispute state only in memory.
- Always refresh critical item state from the backend after claim, listing, checkout, or dispute actions.

## Backend Rules
- All ownership actions must be server-validated.
- Never allow client-side ownership assumptions.
- Never expose secret claim codes in UI, logs, or debug text.
- Listing must be blocked for disputed, frozen, or stolen items.
- Claim must be blocked unless the item is sold_unclaimed and the claim code is valid.

## UX
- Prioritize polished auth, item detail, scan, vault, resale, and dispute flows.
- Add strong loading, empty, success, and error states.
- Use black, gold, and off-white design language.
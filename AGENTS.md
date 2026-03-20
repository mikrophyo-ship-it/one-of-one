# AGENTS.md

## Product Direction
- This project is a premium collectible fashion marketplace, not a generic t-shirt store.
- The product value comes from authenticity, provenance, ownership, exclusivity, and controlled resale.

## Stack Rules
- Use Flutter and Dart for all client apps.
- Customer app should target iOS and Android first.
- Admin app should target Flutter Web first and remain desktop-ready in architecture.
- Use Supabase as the backend system of record.
- Do not introduce blockchain, NFT, or crypto logic.

## Marketplace Rules
- Ownership is server-authoritative only.
- Off-platform sales are not recognized.
- Resale is on-platform only.
- Charge platform transfer fee on every resale.
- Charge artist royalty on every resale.
- Never allow disputed, frozen, or stolen items to be listed, sold, transferred, or claimed.
- Never allow listing by a non-owner.
- Never expose hidden claim codes publicly.

## Engineering Rules
- Keep architecture modular and testable.
- Use shared packages only where they reduce duplication cleanly.
- Do not bury business rules inside UI widgets.
- Prefer maintainable structure over shortcuts.
- Add meaningful tests for critical business rules.
- Ensure analyzer and tests pass before finishing.
- Keep secrets out of client code.

## UX Rules
- Premium visual language only: black, gold, off-white, minimal editorial luxury.
- Avoid generic marketplace components and template styling.
- Customer app is mobile-first.
- Admin app is optimized for operational workflows.

## V2 Hooks
- Keep architecture ready for future NFC/Bluetooth ownership transfer.
- Do not implement NFC/Bluetooth in V1.
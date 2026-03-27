# One of One Roadmap Notes

## Planned Future Scope

### Artist Accounts And Portal
- Add dedicated `artist` and `artist_manager` roles for artist-side access.
- Keep `admin` and `owner` as platform-authoritative operational roles.
- Do not weaken server-authoritative ownership, dispute, resale, or claim rules.

### Artist Portal Goals
- Give artists a dedicated account to review their own marketplace performance.
- Let artists track their own artworks, inventory footprint, sales, resale royalties, and payout status.
- Provide aggregate audience analytics such as profile views, artwork views, saves, and conversion trends.
- Allow controlled profile management for bio, statement, and public-facing artist information.

### Guardrails
- Artists must not gain ownership transfer authority.
- Artists must not approve claims or access hidden claim codes.
- Artists must not override disputes, freeze states, or off-platform ownership rules.
- Artists should receive aggregate analytics, not unrestricted customer private identity data.

### Suggested V1 Scope For Artist Portal
- Artist sign-in
- Artist-to-profile linking through backend-managed role mapping
- Read-only dashboard for:
  - artworks
  - inventory summary
  - sales summary
  - resale royalty summary
  - payout visibility
  - aggregate audience analytics
- Controlled artist profile editing

### Suggested Later Phases
- Artwork draft submission and admin review workflow
- Richer payout ledger details
- Trend reporting and time-series analytics
- Artist team management for multi-user studio accounts

### Implementation Direction
- Prefer secure Supabase RPCs and views over direct table access.
- Add explicit artist-to-user linking so each artist account only sees its own records.
- Keep all hidden claim data private and out of artist-facing surfaces.
- Preserve existing admin authority for moderation, disputes, and catalog enforcement.

-- Safe base seed for One of One.
-- This file intentionally avoids direct writes to auth.users.
-- Create real auth accounts through Supabase Auth, then call public.upsert_my_profile(...)
-- and the authenticated RPCs to claim, list, buy, dispute, or administer items.

insert into public.artists (id, slug, display_name, bio, royalty_bps, authenticity_statement)
values (
  '10000000-0000-0000-0000-000000000001',
  'maya-vale',
  'Maya Vale',
  'Painter and garment intervention artist.',
  1200,
  'Created entirely by Maya Vale using hand-drawn and hand-painted studio process.'
)
on conflict (id) do update set
  slug = excluded.slug,
  display_name = excluded.display_name,
  bio = excluded.bio,
  royalty_bps = excluded.royalty_bps,
  authenticity_statement = excluded.authenticity_statement;

insert into public.artworks (id, artist_id, title, collection_name, concept_note, story, creation_date, provenance_proof)
values (
  '20000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'Afterglow No. 01',
  'Afterglow',
  'Urban reflection studies translated into textile gesture.',
  'Original artwork created for a one-of-one collectible streetwear release.',
  '2026-01-10',
  '["draft-sketch-01.jpg", "studio-process-01.mov", "signed-authenticity.pdf"]'::jsonb
)
on conflict (id) do update set
  artist_id = excluded.artist_id,
  title = excluded.title,
  collection_name = excluded.collection_name,
  concept_note = excluded.concept_note,
  story = excluded.story,
  creation_date = excluded.creation_date,
  provenance_proof = excluded.provenance_proof;

insert into public.garment_products (id, sku, name, silhouette, size_label, colorway, base_price_cents)
values (
  '30000000-0000-0000-0000-000000000001',
  'OOO-AG-TEE-01',
  'Afterglow Hand-Finished Tee',
  'oversized tee',
  'L',
  'black/gold',
  140000
)
on conflict (id) do update set
  sku = excluded.sku,
  name = excluded.name,
  silhouette = excluded.silhouette,
  size_label = excluded.size_label,
  colorway = excluded.colorway,
  base_price_cents = excluded.base_price_cents;

insert into public.unique_items (
  id,
  garment_product_id,
  artwork_id,
  artist_id,
  serial_number,
  public_qr_token,
  hidden_claim_code_hash,
  state,
  current_owner_user_id,
  minted_at,
  listed_price_cents,
  claim_code_consumed_at,
  claim_code_consumed_by,
  claimed_at
) values (
  '40000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'OOO-AG-0001',
  'qr_afterglow_0001',
  encode(digest('CLAIM-OOO-AG-0001', 'sha256'), 'hex'),
  'sold_unclaimed',
  null,
  timezone('utc', now()),
  null,
  null,
  null,
  null
), (
  '40000000-0000-0000-0000-000000000002',
  '30000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'OOO-EM-0002',
  'qr_ember_0002',
  encode(digest('CLAIM-OOO-EM-0002', 'sha256'), 'hex'),
  'sold_unclaimed',
  null,
  timezone('utc', now()),
  null,
  null,
  null,
  null
), (
  '40000000-0000-0000-0000-000000000003',
  '30000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'OOO-RS-0003',
  'qr_restricted_0003',
  encode(digest('CLAIM-OOO-RS-0003', 'sha256'), 'hex'),
  'frozen',
  null,
  timezone('utc', now()),
  null,
  null,
  null,
  null
)
on conflict (id) do update set
  garment_product_id = excluded.garment_product_id,
  artwork_id = excluded.artwork_id,
  artist_id = excluded.artist_id,
  serial_number = excluded.serial_number,
  public_qr_token = excluded.public_qr_token,
  hidden_claim_code_hash = excluded.hidden_claim_code_hash,
  state = excluded.state,
  current_owner_user_id = excluded.current_owner_user_id,
  minted_at = excluded.minted_at,
  listed_price_cents = excluded.listed_price_cents,
  claim_code_consumed_at = excluded.claim_code_consumed_at,
  claim_code_consumed_by = excluded.claim_code_consumed_by,
  claimed_at = excluded.claimed_at;

insert into public.authenticity_records (unique_item_id, authenticity_status, public_story)
values
  ('40000000-0000-0000-0000-000000000001', 'verified', 'Verified collectible with public provenance and private ownership protections.'),
  ('40000000-0000-0000-0000-000000000002', 'verified', 'Eligible for hidden-code claim after fulfilment.'),
  ('40000000-0000-0000-0000-000000000003', 'restricted', 'Restricted ownership status. Contact platform support.')
on conflict (unique_item_id) do update set
  authenticity_status = excluded.authenticity_status,
  public_story = excluded.public_story;

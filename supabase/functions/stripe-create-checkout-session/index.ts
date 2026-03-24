import { createClient } from 'jsr:@supabase/supabase-js@2';

import { createStripeClient, json, requireEnv } from '../_shared/stripe.ts';

const supabaseUrl = requireEnv('SUPABASE_URL');
const supabaseAnonKey = requireEnv('SUPABASE_ANON_KEY');
const supabaseServiceRoleKey = requireEnv('SUPABASE_SERVICE_ROLE_KEY');
const defaultSuccessUrl =
  Deno.env.get('CUSTOMER_APP_CHECKOUT_SUCCESS_URL')?.trim() ?? '';
const defaultCancelUrl =
  Deno.env.get('CUSTOMER_APP_CHECKOUT_CANCEL_URL')?.trim() ?? '';
const defaultCurrency =
  Deno.env.get('STRIPE_CHECKOUT_CURRENCY')?.trim().toLowerCase() || 'usd';
const stripe = createStripeClient();

Deno.serve(async (request: Request) => {
  if (request.method !== 'POST') {
    return json({ error: 'Method not allowed.' }, { status: 405 });
  }

  const authHeader = request.headers.get('Authorization');
  if (!authHeader) {
    return json({ error: 'Missing auth header.' }, { status: 401 });
  }

  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const serviceClient = createClient(supabaseUrl, supabaseServiceRoleKey);

  try {
    const body = (await request.json()) as Record<string, unknown>;
    const itemId = String(body['item_id'] ?? '').trim();
    const successUrl = String(body['success_url'] ?? defaultSuccessUrl).trim();
    const cancelUrl = String(body['cancel_url'] ?? defaultCancelUrl).trim();

    if (itemId.length === 0) {
      return json({ error: 'item_id is required.' }, { status: 400 });
    }
    if (successUrl.length === 0 || cancelUrl.length === 0) {
      return json(
        { error: 'Hosted checkout requires configured success and cancel URLs.' },
        { status: 400 },
      );
    }

    const { data: catalog, error: catalogError } = await userClient
      .from('public_collectible_catalog')
      .select(
        'item_id, listing_id, asking_price_cents, garment_name, serial_number, artwork_title, artist_name',
      )
      .eq('item_id', itemId)
      .single();
    if (catalogError != null) {
      throw new Error(catalogError.message);
    }

    const listingId = catalog['listing_id'];
    if (listingId == null) {
      return json(
        { error: 'This collectible is not available for checkout.' },
        { status: 400 },
      );
    }

    const { data: checkoutSeed, error: checkoutSeedError } = await userClient.rpc(
      'create_resale_checkout_session',
      {
        p_listing_id: listingId,
        p_provider: 'stripe',
        p_success_url: successUrl,
        p_cancel_url: cancelUrl,
      },
    );
    if (checkoutSeedError != null) {
      throw new Error(checkoutSeedError.message);
    }

    const checkout = checkoutSeed as Record<string, unknown>;
    const orderId = String(checkout['order_id'] ?? '').trim();
    const providerReference = String(checkout['provider_reference'] ?? '').trim();
    const amountCents = Number(
      checkout['amount_cents'] ?? catalog['asking_price_cents'] ?? 0,
    );
    const itemLabel = String(
      checkout['item_label'] ?? catalog['serial_number'] ?? itemId,
    ).trim();
    const productName = String(
      catalog['garment_name'] ?? 'One of One collectible',
    ).trim();
    const artistName = String(catalog['artist_name'] ?? '').trim();
    const artworkTitle = String(catalog['artwork_title'] ?? '').trim();

    const session = await stripe.checkout.sessions.create({
      mode: 'payment',
      success_url: successUrl,
      cancel_url: cancelUrl,
      client_reference_id: orderId,
      metadata: {
        order_id: orderId,
        item_id: itemId,
        provider_reference: providerReference,
      },
      line_items: [
        {
          quantity: 1,
          price_data: {
            currency: defaultCurrency,
            unit_amount: amountCents,
            product_data: {
              name: `${productName} / ${itemLabel}`,
              description: [artistName, artworkTitle].filter(Boolean).join(' / '),
            },
          },
        },
      ],
      payment_intent_data: {
        metadata: {
          order_id: orderId,
          item_id: itemId,
          provider_reference: providerReference,
        },
      },
    });

    const { error: attachError } = await serviceClient.rpc(
      'attach_checkout_provider_session',
      {
        p_order_id: orderId,
        p_provider: 'stripe',
        p_provider_reference: providerReference,
        p_provider_session_reference: session.id,
        p_checkout_session_id: session.id,
        p_checkout_url: session.url,
        p_currency: defaultCurrency,
        p_provider_payload: {
          livemode: session.livemode,
          payment_status: session.payment_status,
        },
      },
    );
    if (attachError != null) {
      throw new Error(attachError.message);
    }

    return json({
      order_id: orderId,
      provider: 'stripe',
      status: session.status ?? 'open',
      provider_reference: providerReference,
      checkout_url: session.url,
      client_secret: null,
      expires_at:
        session.expires_at == null
          ? null
          : new Date(session.expires_at * 1000).toISOString(),
    });
  } catch (error) {
    return json(
      {
        error:
          error instanceof Error
            ? error.message
            : 'Unable to create checkout session.',
      },
      { status: 400 },
    );
  }
});

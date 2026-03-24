import { createClient } from 'jsr:@supabase/supabase-js@2';

import {
  createStripeClient,
  json,
  orderIdFromStripeObject,
  requireEnv,
} from '../_shared/stripe.ts';

const supabaseUrl = requireEnv('SUPABASE_URL');
const serviceRoleKey = requireEnv('SUPABASE_SERVICE_ROLE_KEY');
const webhookSecret = requireEnv('STRIPE_WEBHOOK_SECRET');
const stripe = createStripeClient();
const serviceClient = createClient(supabaseUrl, serviceRoleKey);

async function findOrderIdForRefund(
  refund: Record<string, unknown>,
): Promise<string | null> {
  const metadataOrderId = orderIdFromStripeObject(refund);
  if (metadataOrderId != null) {
    return metadataOrderId;
  }

  const paymentIntentId =
    typeof refund['payment_intent'] === 'string'
      ? refund['payment_intent']
      : null;
  if (paymentIntentId != null) {
    const { data } = await serviceClient
      .from('payments')
      .select('order_id')
      .eq('payment_intent_id', paymentIntentId)
      .limit(1)
      .maybeSingle();
    if (data != null) {
      return String(data['order_id']);
    }
  }

  const chargeId =
    typeof refund['charge'] === 'string' ? refund['charge'] : null;
  if (chargeId != null) {
    const { data } = await serviceClient
      .from('payments')
      .select('order_id')
      .eq('latest_charge_id', chargeId)
      .limit(1)
      .maybeSingle();
    if (data != null) {
      return String(data['order_id']);
    }
  }

  return null;
}

Deno.serve(async (request: Request) => {
  if (request.method !== 'POST') {
    return json({ error: 'Method not allowed.' }, { status: 405 });
  }

  const signature = request.headers.get('Stripe-Signature');
  if (!signature) {
    return json({ error: 'Missing Stripe signature.' }, { status: 400 });
  }

  let eventId = 'unknown';
  try {
    const body = await request.text();
    const event = await stripe.webhooks.constructEventAsync(
      body,
      signature,
      webhookSecret,
    );
    eventId = event.id;

    const { data: webhookLog, error: webhookLogError } = await serviceClient.rpc(
      'record_payment_provider_webhook_event',
      {
        p_provider: 'stripe',
        p_provider_event_id: event.id,
        p_event_type: event.type,
        p_payload: event as unknown as Record<string, unknown>,
        p_api_version: event.api_version,
        p_livemode: event.livemode,
      },
    );
    if (webhookLogError != null) {
      throw new Error(webhookLogError.message);
    }

    const logResult = webhookLog as Record<string, unknown>;
    if (logResult['already_processed'] === true) {
      return json({ received: true, duplicate: true });
    }

    const object = event.data.object as unknown as Record<string, unknown>;
    let orderId = orderIdFromStripeObject(object);
    let paymentId: string | null = null;
    let refundId: string | null = null;

    switch (event.type) {
      case 'checkout.session.completed':
      case 'checkout.session.async_payment_succeeded': {
        const amount = Number(object['amount_total'] ?? 0);
        const providerReference =
          typeof object['payment_intent'] === 'string'
            ? object['payment_intent']
            : String(object['id'] ?? '');
        if (orderId == null) {
          throw new Error('Stripe checkout event missing order_id metadata.');
        }
        const { data, error } = await serviceClient.rpc(
          'mark_resale_payment_authorized',
          {
            p_order_id: orderId,
            p_provider: 'stripe',
            p_provider_reference: providerReference,
            p_amount_cents: amount,
          },
        );
        if (error != null) {
          throw new Error(error.message);
        }
        const result = data as Record<string, unknown>;
        paymentId =
          result['payment_id'] == null ? null : String(result['payment_id']);
        break;
      }
      case 'checkout.session.expired':
      case 'checkout.session.async_payment_failed':
      case 'payment_intent.payment_failed': {
        if (orderId == null) {
          const paymentIntentMetadata =
            object['metadata'] as Record<string, unknown> | undefined;
          orderId = orderIdFromStripeObject(paymentIntentMetadata);
        }
        if (orderId == null) {
          throw new Error('Stripe failure event missing order_id metadata.');
        }
        const providerReference =
          typeof object['payment_intent'] === 'string'
            ? object['payment_intent']
            : String(object['id'] ?? '');
        const { error } = await serviceClient.rpc(
          'mark_resale_payment_failed_or_expired',
          {
            p_order_id: orderId,
            p_provider: 'stripe',
            p_provider_reference: providerReference,
            p_reason: `Stripe event ${event.type}`,
          },
        );
        if (error != null) {
          throw new Error(error.message);
        }
        break;
      }
      case 'refund.updated':
      case 'refund.failed': {
        orderId = await findOrderIdForRefund(object);
        if (orderId == null) {
          throw new Error('Unable to resolve order for Stripe refund event.');
        }
        const { data, error } = await serviceClient.rpc(
          'reconcile_order_refund',
          {
            p_order_id: orderId,
            p_provider: 'stripe',
            p_provider_reference: String(object['id'] ?? ''),
            p_amount_cents: Number(object['amount'] ?? 0),
            p_reason: String(object['reason'] ?? 'requested_by_customer'),
            p_status: String(object['status'] ?? 'pending'),
            p_note: `Stripe webhook ${event.type}`,
            p_provider_payload: object,
          },
        );
        if (error != null) {
          throw new Error(error.message);
        }
        const result = data as Record<string, unknown>;
        refundId = result['refund_id'] == null ? null : String(result['refund_id']);
        break;
      }
      default: {
        await serviceClient.rpc('mark_payment_provider_webhook_event_state', {
          p_provider: 'stripe',
          p_provider_event_id: event.id,
          p_processing_state: 'ignored',
          p_order_id: orderId,
          p_payment_id: paymentId,
          p_refund_id: refundId,
          p_error_message: null,
        });
        return json({ received: true, ignored: true, event_type: event.type });
      }
    }

    await serviceClient.rpc('mark_payment_provider_webhook_event_state', {
      p_provider: 'stripe',
      p_provider_event_id: event.id,
      p_processing_state: 'processed',
      p_order_id: orderId,
      p_payment_id: paymentId,
      p_refund_id: refundId,
      p_error_message: null,
    });

    return json({ received: true, event_type: event.type, order_id: orderId });
  } catch (error) {
    await serviceClient
      .rpc('mark_payment_provider_webhook_event_state', {
        p_provider: 'stripe',
        p_provider_event_id: eventId,
        p_processing_state: 'failed',
        p_order_id: null,
        p_payment_id: null,
        p_refund_id: null,
        p_error_message:
          error instanceof Error ? error.message : 'Webhook processing failed.',
      })
      .catch(() => null);

    return json(
      {
        error:
          error instanceof Error ? error.message : 'Webhook processing failed.',
      },
      { status: 400 },
    );
  }
});

# One of One Payment Configuration

## Goals
- Keep client apps on public, non-secret configuration only.
- Keep Stripe secret keys and webhook secrets in Supabase Edge Function environment variables.
- Separate local, staging, and production return URLs and Stripe accounts cleanly.

## Client-Safe Dart Defines
Use these only in Flutter apps:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `CHECKOUT_SUCCESS_URL`
- `CHECKOUT_CANCEL_URL`

The customer app uses the success and cancel URLs only to start hosted checkout and show return-state messaging. Payment authorization and settlement still reconcile through webhook-driven backend state.

## Edge Function Secrets
Set these on the Supabase project hosting `stripe-create-checkout-session` and `stripe-webhook`:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_CHECKOUT_CURRENCY`
- `CUSTOMER_APP_CHECKOUT_SUCCESS_URL`
- `CUSTOMER_APP_CHECKOUT_CANCEL_URL`

Do not ship `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, or `SUPABASE_SERVICE_ROLE_KEY` to any Flutter client build.

## Local
- Use a Stripe test account.
- Set `CHECKOUT_SUCCESS_URL` and `CHECKOUT_CANCEL_URL` to your local web or simulator deep-link endpoint.
- Point Stripe webhook delivery to a tunnel or local relay that forwards to the deployed `stripe-webhook` function.
- Subscribe at minimum to:
  `checkout.session.completed`
  `checkout.session.async_payment_succeeded`
  `checkout.session.async_payment_failed`
  `checkout.session.expired`
  `payment_intent.payment_failed`
  `refund.updated`
  `refund.failed`

## Staging
- Use a dedicated Stripe test or restricted staging account, not the local shared account.
- Use staging Supabase with separate service role and webhook secret.
- Use staging return URLs only.
- Validate duplicate webhook delivery, delayed async success, and repeated refund updates before promoting.

## Production
- Use a production Stripe account and production webhook endpoint secret only in production.
- Keep a distinct production Supabase project or strictly isolated function secret set.
- Use HTTPS-only return URLs and production app deep links.
- Rotate `STRIPE_WEBHOOK_SECRET` and `STRIPE_SECRET_KEY` independently of lower environments.
- Review Stripe livemode delivery and Supabase function logs during rollout.

## Webhook Processing Model
- `stripe-webhook` verifies the `Stripe-Signature` header before processing.
- Every provider event is persisted to `payment_provider_webhook_events`.
- Processing is idempotent by `(provider, provider_event_id)`.
- Payment authorization updates only advance orders that are still pending.
- Failure or expiry events reopen the listing only before delivery finalization.
- Refund reconciliation caps cumulative refunds at the captured payment amount.
- Repeated or delayed refund events update the same refund record by provider reference.

## Settlement Guardrails
- Payment completion does not finalize ownership on its own.
- Ownership finalizes only after delivery confirmation.
- Payout release happens only when:
  the order is fulfilled,
  delivery is confirmed,
  a delivered shipment event exists,
  no open dispute exists,
  and no refund has been recorded.

## Deployment Checklist
1. Apply migrations through `0010_stripe_checkout_reconciliation.sql`.
2. Deploy `stripe-create-checkout-session`.
3. Deploy `stripe-webhook`.
4. Set function secrets for the target environment.
5. Configure Stripe webhook subscriptions for that environment.
6. Smoke test checkout success, checkout cancel, expiry, payment failure, partial refund, and full refund before enabling real traffic.

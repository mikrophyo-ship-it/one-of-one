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
- `APP_ENV`
- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_CHECKOUT_CURRENCY`
- `CUSTOMER_APP_CHECKOUT_SUCCESS_URL`
- `CUSTOMER_APP_CHECKOUT_CANCEL_URL`

Do not ship `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, or `SUPABASE_SERVICE_ROLE_KEY` to any Flutter client build.

## Environment-Specific Loading
The shared Stripe loader checks `APP_ENV` first and tries environment-scoped variables before the generic names.

Examples when `APP_ENV=local`:
- `STRIPE_SECRET_KEY_LOCAL` before `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET_LOCAL` before `STRIPE_WEBHOOK_SECRET`
- `CUSTOMER_APP_CHECKOUT_SUCCESS_URL_LOCAL` before `CUSTOMER_APP_CHECKOUT_SUCCESS_URL`
- `CUSTOMER_APP_CHECKOUT_CANCEL_URL_LOCAL` before `CUSTOMER_APP_CHECKOUT_CANCEL_URL`

Recommended profiles:
- `APP_ENV=local`
- `APP_ENV=staging`
- `APP_ENV=production`

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
- Use the signing secret printed by `stripe listen` as `STRIPE_WEBHOOK_SECRET_LOCAL`.
- The helper script `scripts/stripe/stripe_test_mode_commands.ps1 -PrintOnly` prints the exact command set used in this repository.

## Staging
- Use a dedicated Stripe test or restricted staging account, not the local shared account.
- Use staging Supabase with separate service role and webhook secret.
- Use staging return URLs only.
- Prefer a Stripe-registered staging webhook endpoint. Use `stripe listen --load-from-webhooks-api --forward-to ...` only when you need to mirror staging traffic into a local debugger.
- Validate duplicate webhook delivery, delayed async success, and repeated refund updates before promoting.

## Production
- Use a production Stripe account and production webhook endpoint secret only in production.
- Keep a distinct production Supabase project or strictly isolated function secret set.
- Use HTTPS-only return URLs and production app deep links.
- Rotate `STRIPE_WEBHOOK_SECRET` and `STRIPE_SECRET_KEY` independently of lower environments.
- Review Stripe livemode delivery and Supabase function logs during rollout.

## Webhook Processing Model
- `stripe-webhook` verifies the `Stripe-Signature` header before processing.
- Verification happens against the raw request body through `stripe.webhooks.constructEventAsync(...)` before any event payload is trusted.
- Every provider event is persisted to `payment_provider_webhook_events`.
- Processing is idempotent by `(provider, provider_event_id)`.
- Stripe object references used by later reconciliation are persisted back to `payments`, including `checkout_session_id`, `payment_intent_id`, `latest_charge_id`, and the last processed webhook metadata.
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
1. Apply migrations through `0011_payment_reconciliation_refs.sql`.
2. Deploy `stripe-create-checkout-session`.
3. Deploy `stripe-webhook`.
4. Set function secrets for the target environment.
5. Configure Stripe webhook subscriptions for that environment.
6. Smoke test checkout success, checkout cancel, expiry, payment failure, partial refund, and full refund before enabling real traffic.

## Stripe CLI Commands
Forward the exact event set used by the hardened reconciliation flow:

```powershell
stripe listen --events checkout.session.completed,checkout.session.async_payment_succeeded,checkout.session.async_payment_failed,checkout.session.expired,payment_intent.payment_failed,refund.updated,refund.failed --forward-to http://127.0.0.1:54321/functions/v1/stripe-webhook
```

Trigger events in test mode:

```powershell
stripe trigger checkout.session.completed
stripe trigger checkout.session.async_payment_succeeded
stripe trigger checkout.session.async_payment_failed
stripe trigger checkout.session.expired
stripe trigger payment_intent.payment_failed
stripe trigger refund.updated
stripe trigger refund.failed
```

To confirm local CLI support on your installed Stripe CLI version:

```powershell
stripe listen --help
stripe trigger --help
```

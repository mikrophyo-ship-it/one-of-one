param(
  [string]$ForwardTo = "http://127.0.0.1:54321/functions/v1/stripe-webhook",
  [switch]$PrintOnly
)

$events = @(
  "checkout.session.completed",
  "checkout.session.async_payment_succeeded",
  "checkout.session.async_payment_failed",
  "checkout.session.expired",
  "payment_intent.payment_failed",
  "refund.updated",
  "refund.failed"
)

$listenCommand = "stripe listen --events " + ($events -join ",") + " --forward-to $ForwardTo"

$commands = @(
  $listenCommand,
  "stripe trigger checkout.session.completed",
  "stripe trigger checkout.session.async_payment_succeeded",
  "stripe trigger checkout.session.async_payment_failed",
  "stripe trigger checkout.session.expired",
  "stripe trigger payment_intent.payment_failed",
  "stripe trigger refund.updated",
  "stripe trigger refund.failed"
)

if ($PrintOnly) {
  $commands | ForEach-Object { $_ }
  exit 0
}

Write-Host "Stripe test-mode command checklist:`n"
$commands | ForEach-Object { Write-Host $_ }

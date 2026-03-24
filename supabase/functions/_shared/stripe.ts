import Stripe from 'npm:stripe@18.4.0';

export function requireEnv(name: string): string {
  const value = getEnv(name);
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

export function createStripeClient(): Stripe {
  return new Stripe(requireEnv('STRIPE_SECRET_KEY'));
}

export function getEnv(name: string): string | undefined {
  const appEnv = (Deno.env.get('APP_ENV') ?? '').trim().toUpperCase();
  const candidates = appEnv.length === 0 ? [name] : [`${name}_${appEnv}`, name];

  for (const candidate of candidates) {
    const value = Deno.env.get(candidate)?.trim();
    if (value && value.length > 0) {
      return value;
    }
  }

  return undefined;
}

export function json(
  body: Record<string, unknown>,
  init: ResponseInit = {},
): Response {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: {
      'content-type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
}

export function orderIdFromStripeObject(
  value: Record<string, unknown> | null | undefined,
): string | null {
  if (!value) {
    return null;
  }

  const metadata = value['metadata'];
  if (metadata && typeof metadata === 'object') {
    const orderId = (metadata as Record<string, unknown>)['order_id'];
    if (typeof orderId === 'string' && orderId.trim().length > 0) {
      return orderId.trim();
    }
  }

  const clientReferenceId = value['client_reference_id'];
  if (
    typeof clientReferenceId === 'string' &&
    clientReferenceId.trim().length > 0
  ) {
    return clientReferenceId.trim();
  }

  return null;
}

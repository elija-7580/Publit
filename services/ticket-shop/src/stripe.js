// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// The few Stripe calls the shop needs, without the SDK. Card data never reaches Publit: the customer pays on
// Stripe's hosted checkout page (cards, Apple Pay, Google Pay …), so Publit stays at PCI DSS SAQ A.
// Payments are only authorised at first (capture_method=manual) and captured once the tickets are booked.

const API = "https://api.stripe.com/v1";

/** Stripe's form encoding: a[b][0][c]=… */
export function form(value, prefix = "", out = new URLSearchParams()) {
  if (value === undefined || value === null) return out;
  if (Array.isArray(value)) {
    value.forEach((item, i) => form(item, `${prefix}[${i}]`, out));
  } else if (typeof value === "object") {
    for (const [k, v] of Object.entries(value)) form(v, prefix ? `${prefix}[${k}]` : k, out);
  } else {
    out.append(prefix, String(value));
  }
  return out;
}

export class StripeError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export function stripe(secretKey, fetchImpl = fetch) {
  async function call(method, path, params, idempotencyKey) {
    const headers = { Authorization: `Bearer ${secretKey}` };
    let body;
    if (params && method !== "GET") {
      headers["Content-Type"] = "application/x-www-form-urlencoded";
      body = form(params).toString();
    }
    if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;
    const query = params && method === "GET" ? `?${form(params).toString()}` : "";
    const response = await fetchImpl(`${API}${path}${query}`, { method, headers, body });
    const json = await response.json().catch(() => null);
    if (!response.ok) throw new StripeError(response.status, json?.error?.message ?? `Stripe HTTP ${response.status}`);
    return json;
  }

  return {
    createCheckout(params) { return call("POST", "/checkout/sessions", params); },
    session(id) { return call("GET", `/checkout/sessions/${encodeURIComponent(id)}`, { expand: ["payment_intent"] }); },
    capture(intentId, amount, key) {
      return call("POST", `/payment_intents/${encodeURIComponent(intentId)}/capture`, { amount_to_capture: amount }, key);
    },
    cancel(intentId, key) { return call("POST", `/payment_intents/${encodeURIComponent(intentId)}/cancel`, {}, key); },
    setMetadata(intentId, metadata) { return call("POST", `/payment_intents/${encodeURIComponent(intentId)}`, { metadata }); },
  };
}

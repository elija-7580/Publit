// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Publit ticket shop: the app asks for offers for a journey, opens one checkout for all legs and gets the
// tickets back. Provider API keys and the Stripe key stay here, never in the app. Nothing is stored or logged.
//
//   POST /v1/offers                  { legs, adults, currency, locale }        → { offers, providers }
//   POST /v1/checkout                { offers: [token], customer, termsAccepted } → { order, paymentURL, amount, currency }
//   GET  /v1/return                  Stripe returns here; redirects to publit://shop/return?…
//   POST /v1/orders/{order}/complete                                          → { status, amountCharged, items }
//   GET/POST /v1/demo-pay            only with DEMO_PAYMENTS="on": a payment page that charges nothing
//
// Open ticket-link layer (any app, no keys needed, see links.js):
//   GET  /v1/partners                                                         → { programs }
//   POST /v1/links                   { legs, partners? }                      → { links }

import { checkout, complete, findOffers, ShopError } from "./shop.js";
import { stripe as stripeClient, StripeError } from "./stripe.js";
import { ProviderError } from "./providers/errors.js";
import { demoPayments, demoPaymentsActive } from "./demopay.js";
import { findLinks, partners } from "./links.js";

let demoPay = null;

const MAX_BODY = 64 * 1024;

// The link layer is public, so web apps may call it from the browser.
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type", "Access-Control-Max-Age": "86400" };

function json(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...headers },
  });
}

function failure(code, message, status) {
  return json({ error: code, message }, status);
}

async function readJSON(request) {
  const length = Number(request.headers.get("Content-Length") ?? "0");
  if (length > MAX_BODY) throw new ShopError(413, "too_large", "Payload too large");
  const text = await request.text();
  if (text.length > MAX_BODY) throw new ShopError(413, "too_large", "Payload too large");
  try {
    return JSON.parse(text);
  } catch {
    throw new ShopError(400, "invalid", "Invalid JSON");
  }
}

export function returnRedirect(url) {
  const session = url.searchParams.get("session_id");
  const target = new URL("publit://shop/return");
  if (session && /^cs_[A-Za-z0-9_]{8,200}$/.test(session)) target.searchParams.set("order", session);
  else target.searchParams.set("cancelled", "1");
  return new Response(null, { status: 302, headers: { Location: target.toString(), "Cache-Control": "no-store" } });
}

export default {
  async fetch(request, env, ctx, deps = {}) {
    const url = new URL(request.url);
    const fetchImpl = deps.fetch ?? fetch;
    try {
      if (url.pathname === "/v1/return" && request.method === "GET") return returnRedirect(url);
      const demo = deps.demoPay ?? (demoPaymentsActive(env) ? (demoPay ??= demoPayments()) : null);
      if (url.pathname === "/v1/demo-pay" && demo) return demo.page(request);
      const isLinks = url.pathname === "/v1/links" || url.pathname === "/v1/partners";
      if (isLinks && request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
      if (url.pathname === "/v1/partners" && request.method === "GET") {
        return json(partners(env), 200, { ...CORS, "Cache-Control": "public, max-age=3600" });
      }
      if (request.method !== "POST") return failure("not_found", "Not found", 404);
      if (env.RATE_LIMITER) {
        const { success } = await env.RATE_LIMITER.limit({ key: request.headers.get("CF-Connecting-IP") ?? "unknown" });
        if (!success) return failure("rate_limited", "Too many requests", 429);
      }
      if (url.pathname === "/v1/links") {
        try {
          return json(findLinks(await readJSON(request), env), 200, CORS);
        } catch (error) {
          if (error instanceof ShopError) return json({ error: error.code, message: error.message }, error.status, CORS);
          throw error;
        }
      }
      if (!env.TOKEN_SECRET) return failure("not_configured", "Shop not configured", 503);
      const stripe = deps.stripe ?? (env.STRIPE_SECRET_KEY ? stripeClient(env.STRIPE_SECRET_KEY, fetchImpl) : demo);

      if (url.pathname === "/v1/offers") {
        return json(await findOffers(await readJSON(request), env, { fetchImpl }));
      }
      if (!stripe) return failure("not_configured", "Payments not configured", 503);
      if (url.pathname === "/v1/checkout") {
        return json(await checkout(await readJSON(request), env, { stripe, origin: url.origin, fetchImpl }));
      }
      const match = url.pathname.match(/^\/v1\/orders\/([^/]+)\/complete$/);
      if (match) return json(await complete(decodeURIComponent(match[1]), env, { stripe, fetchImpl }));
      return failure("not_found", "Not found", 404);
    } catch (error) {
      if (error instanceof ShopError) return failure(error.code, error.message, error.status);
      if (error instanceof ProviderError) return failure("provider", error.message, 502);
      if (error instanceof StripeError) return failure("payment", "Payment service error", 502);
      return failure("internal", "Something went wrong", 500);
    }
  },
};

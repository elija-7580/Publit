// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// One purchase for a whole journey: offers for each leg from whichever provider sells it, one payment for all
// of them, then a booking per leg. If a leg cannot be booked after paying, only the booked legs are charged.
// Nothing is stored on this server: offers travel as signed tokens and the order lives in the Stripe payment.

import { active, provider as providerById, providers as allProviders } from "./providers/index.js";
import { ProviderError } from "./providers/errors.js";
import { sign, verify } from "./token.js";

export class ShopError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

const MAX_LEGS = 12;
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$/;

function text(value, max) {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") throw new ShopError(400, "invalid", "Invalid text");
  const trimmed = value.trim();
  if (trimmed.length > max) throw new ShopError(400, "invalid", "Text too long");
  return trimmed || null;
}

function place(value) {
  if (!value || typeof value !== "object") throw new ShopError(400, "invalid", "Missing place");
  const lat = Number(value.lat), lon = Number(value.lon);
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
    throw new ShopError(400, "invalid", "Invalid coordinates");
  }
  return { name: text(value.name, 200) ?? "", lat, lon, tz: text(value.tz, 64), stopId: text(value.stopId, 200) };
}

export function parseOfferRequest(body) {
  if (!body || !Array.isArray(body.legs) || body.legs.length === 0 || body.legs.length > MAX_LEGS) {
    throw new ShopError(400, "invalid", "legs: 1 to 12 journey legs");
  }
  const adults = body.adults === undefined ? 1 : Number(body.adults);
  if (!Number.isInteger(adults) || adults < 1 || adults > 9) throw new ShopError(400, "invalid", "adults: 1 to 9");
  const currency = body.currency === undefined ? "EUR" : String(body.currency);
  if (!/^[A-Z]{3}$/.test(currency)) throw new ShopError(400, "invalid", "currency: ISO 4217");
  const locale = body.locale === undefined ? "en" : String(body.locale);
  if (!/^[a-z]{2}$/.test(locale)) throw new ShopError(400, "invalid", "locale: two letters");
  const legs = body.legs.map((leg, i) => {
    if (!leg || typeof leg !== "object") throw new ShopError(400, "invalid", "Invalid leg");
    if (!ISO.test(String(leg.departure)) || !ISO.test(String(leg.arrival))) throw new ShopError(400, "invalid", "Times: ISO 8601 with offset");
    return {
      index: Number.isInteger(leg.index) ? leg.index : i,
      mode: (text(leg.mode, 40) ?? "").toUpperCase(),
      line: text(leg.line, 80),
      operator: text(leg.operator, 120),
      from: place(leg.from),
      to: place(leg.to),
      departure: leg.departure,
      arrival: leg.arrival,
    };
  });
  return { legs, adults, currency, locale };
}

/** For every leg the first provider's offer (or none), each as a signed token the app sends back at checkout. */
export async function findOffers(body, env, { list = allProviders, fetchImpl = fetch } = {}) {
  const request = parseOfferRequest(body);
  const sellers = active(env, list);
  const results = await Promise.all(request.legs.map(async (leg) => {
    for (const p of sellers) {
      if (!p.covers(leg)) continue;
      let found = [];
      try {
        found = await p.offers(leg, request, env, fetchImpl);
      } catch {
        continue; // one provider failing must not hide the others
      }
      const offer = found[0];
      if (!offer) continue;
      const token = await sign({ p: p.id, leg: leg.index, d: offer.data, t: offer.title, o: offer.operator,
        f: leg.from.name, to: leg.to.name, dep: leg.departure, arr: leg.arrival }, env.TOKEN_SECRET);
      return { leg: leg.index, provider: p.id, providerName: p.name, title: offer.title, operator: offer.operator,
        amount: offer.amount, currency: offer.currency, refundable: offer.refundable ?? null, token };
    }
    return null;
  }));
  return { offers: results.filter(Boolean), providers: sellers.map((p) => p.id) };
}

function parseCustomer(value) {
  const firstName = text(value?.firstName, 50), lastName = text(value?.lastName, 50), email = text(value?.email, 254);
  if (!firstName || !lastName) throw new ShopError(400, "invalid", "Name required");
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new ShopError(400, "invalid", "E-mail required");
  return { firstName, lastName, email };
}

function short(value, max = 60) {
  return value == null ? null : String(value).slice(0, max);
}

function metadataValue(object) {
  const json = JSON.stringify(object);
  if (json.length > 500) throw new ShopError(500, "metadata", "Order item too large");
  return json;
}

/** Reserves every offer, then opens one Stripe checkout for all of them. */
export async function checkout(body, env, { stripe, origin, fetchImpl = fetch, now = Date.now() } = {}) {
  if (body?.termsAccepted !== true) throw new ShopError(400, "terms", "Terms must be accepted");
  const customer = parseCustomer(body?.customer);
  const tokens = Array.isArray(body?.offers) ? body.offers : [];
  if (tokens.length === 0 || tokens.length > MAX_LEGS) throw new ShopError(400, "invalid", "offers: 1 to 12");
  const offers = await Promise.all(tokens.map((t) => verify(t, env.TOKEN_SECRET, now)));
  if (offers.some((o) => !o)) throw new ShopError(410, "expired", "An offer has expired. Search again.");
  if (new Set(offers.map((o) => o.leg)).size !== offers.length) throw new ShopError(400, "invalid", "One offer per leg");

  const settled = await Promise.allSettled(offers.map(async (o) => {
    const p = providerById(o.p);
    if (!p || !p.enabled(env)) throw new ProviderError(o.p, 503, "Seller not available");
    return { offer: o, provider: p, reservation: await p.reserve(o.d, customer, env, fetchImpl) };
  }));
  const failed = settled.findIndex((s) => s.status === "rejected");
  if (failed >= 0) {
    await Promise.all(settled.filter((s) => s.status === "fulfilled")
      .map((s) => s.value.provider.cancel(s.value.reservation.ref, env, fetchImpl).catch(() => {})));
    throw new ShopError(409, "unavailable", `Leg ${offers[failed].leg + 1} can no longer be booked.`);
  }
  const items = settled.map((s) => s.value);
  const currency = items[0].reservation.currency;
  if (items.some((i) => i.reservation.currency !== currency)) throw new ShopError(409, "currency", "Mixed currencies");

  const metadata = { c: metadataValue(customer), n: String(items.length) };
  items.forEach((item, i) => {
    metadata[`r${i}`] = metadataValue({ p: item.provider.id, ref: item.reservation.ref, a: item.reservation.amount,
      l: item.offer.leg, t: short(item.offer.t), o: short(item.offer.o, 40), f: short(item.offer.f, 50),
      to: short(item.offer.to, 50), dep: item.offer.dep, arr: item.offer.arr });
  });
  const total = items.reduce((sum, i) => sum + i.reservation.amount, 0);
  const session = await stripe.createCheckout({
    mode: "payment",
    customer_email: customer.email,
    locale: "auto",
    line_items: items.map((i) => ({
      quantity: 1,
      price_data: {
        currency: currency.toLowerCase(),
        unit_amount: i.reservation.amount,
        product_data: { name: [i.offer.o, `${i.offer.f} → ${i.offer.to}`].filter(Boolean).join(": ").slice(0, 120) },
      },
    })),
    payment_intent_data: { capture_method: "manual", description: "Publit tickets", metadata },
    success_url: `${origin}/v1/return?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${origin}/v1/return?cancelled=1`,
    expires_at: Math.floor(now / 1000) + 31 * 60,
  });
  return { order: session.id, paymentURL: session.url, amount: total, currency };
}

function items(metadata) {
  const count = Number(metadata?.n ?? 0);
  return Array.from({ length: count }, (_, i) => JSON.parse(metadata[`r${i}`]));
}

/** After the payment is authorised: books every leg, charges only what was booked and returns the tickets. */
export async function complete(orderId, env, { stripe, fetchImpl = fetch } = {}) {
  if (!/^cs_[A-Za-z0-9_]{8,200}$/.test(String(orderId))) throw new ShopError(400, "invalid", "Unknown order");
  const session = await stripe.session(orderId);
  const intent = session?.payment_intent;
  if (!intent || typeof intent !== "object") throw new ShopError(402, "unpaid", "Not paid yet");
  if (intent.status === "canceled") throw new ShopError(410, "cancelled", "This order was cancelled and not charged.");
  if (intent.status !== "requires_capture" && intent.status !== "succeeded") throw new ShopError(402, "unpaid", "Not paid yet");

  const metadata = intent.metadata ?? {};
  const customer = JSON.parse(metadata.c ?? "{}");
  const list = items(metadata);
  const bookings = list.map((_, i) => (metadata[`b${i}`] ? JSON.parse(metadata[`b${i}`]) : null));

  if (intent.status === "requires_capture") {
    for (const [i, item] of list.entries()) {
      if (bookings[i]) continue;
      const p = providerById(item.p);
      try {
        bookings[i] = await p.confirm(item.ref, customer, env, fetchImpl);
      } catch {
        bookings[i] = { failed: true };
        await p?.cancel(item.ref, env, fetchImpl).catch(() => {});
      }
      try {
        await stripe.setMetadata(intent.id, { [`b${i}`]: metadataValue(bookings[i]) });
      } catch {
        // Only the record of the booking is missing; a repeated call finds the reservation confirmed.
      }
    }
    const amount = list.reduce((sum, item, i) => sum + (bookings[i]?.failed ? 0 : item.a), 0);
    if (amount > 0) await stripe.capture(intent.id, amount, `capture-${intent.id}`);
    else await stripe.cancel(intent.id, `cancel-${intent.id}`);
  }

  const result = await Promise.all(list.map(async (item, i) => {
    const booking = bookings[i];
    if (!booking || booking.failed) return { leg: item.l, status: "failed", amount: item.a, tickets: [] };
    let tickets = [];
    try {
      tickets = await providerById(item.p).tickets(booking, env, fetchImpl, customer);
    } catch {
      return { leg: item.l, status: "pending", amount: item.a, tickets: [] };
    }
    return {
      leg: item.l, status: "booked", amount: item.a,
      tickets: tickets.map((t) => ({
        title: t.title ?? item.t ?? "Ticket",
        operator: t.operator ?? item.o ?? null,
        origin: t.origin ?? item.f ?? null,
        destination: t.destination ?? item.to ?? null,
        validFrom: t.validFrom ?? item.dep ?? null,
        validUntil: t.validUntil ?? item.arr ?? null,
        passenger: t.passenger ?? `${customer.firstName ?? ""} ${customer.lastName ?? ""}`.trim(),
        reference: t.reference ?? null,
        barcode: t.barcode ?? null,
        pdf: t.pdf ?? null,
      })),
    };
  }));
  const charged = result.filter((r) => r.status !== "failed").reduce((sum, r) => sum + r.amount, 0);
  const status = result.every((r) => r.status === "booked") ? "booked" : charged === 0 ? "failed" : "partial";
  return { status, amountCharged: charged, currency: String(session.currency ?? "").toUpperCase(), items: result };
}

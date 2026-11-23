// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Test provider: offers a made-up ticket for every transit leg, so the whole purchase (offer, Stripe test
// payment, ticket in the wallet) can be tried before any real contract exists. Only on with DEMO_PROVIDER="on";
// never enable it with live Stripe keys. Its tickets say clearly that they are not valid.

const KM = 111.32;

function distanceKm(a, b) {
  const dLat = (a.lat - b.lat) * KM;
  const dLon = (a.lon - b.lon) * KM * Math.cos(((a.lat + b.lat) / 2) * Math.PI / 180);
  return Math.hypot(dLat, dLon);
}

export const demo = {
  id: "demo",
  name: "Publit demo",

  enabled(env) {
    return env.DEMO_PROVIDER === "on" && !String(env.STRIPE_SECRET_KEY ?? "").startsWith("sk_live_");
  },

  covers(leg) {
    return leg.mode !== "WALK" && leg.mode !== "BIKE" && leg.mode !== "CAR";
  },

  async offers(leg, request) {
    const cents = Math.round((250 + distanceKm(leg.from, leg.to) * 12) / 10) * 10;
    return [{
      title: "Demo ticket",
      operator: leg.operator ?? "Demo",
      amount: cents * request.adults,
      currency: request.currency,
      refundable: true,
      data: { from: leg.from.name, to: leg.to.name, departure: leg.departure, arrival: leg.arrival, operator: leg.operator ?? "Demo",
        line: leg.line ?? null, adults: request.adults, amount: cents * request.adults, currency: request.currency },
    }];
  },

  async reserve(data) {
    return { ref: { id: `demo-${crypto.randomUUID()}` }, amount: data.amount, currency: data.currency,
      expiresAt: new Date(Date.now() + 20 * 60000).toISOString() };
  },

  async confirm(ref) {
    return { booking: ref.id };
  },

  /** Route, times and passenger are filled in from the order. */
  async tickets(booking) {
    return [{
      title: "DEMO – not a valid ticket",
      reference: booking.booking,
      barcode: { format: "qr", message: `PUBLIT-DEMO:${booking.booking}` },
    }];
  },

  async cancel() {},
};

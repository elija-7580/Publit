// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import { test } from "node:test";
import assert from "node:assert/strict";
import { sign, verify } from "../src/token.js";
import { checkout, complete, findOffers, parseOfferRequest, ShopError } from "../src/shop.js";
import { distribusion, _test } from "../src/providers/distribusion.js";
import { form } from "../src/stripe.js";
import worker, { returnRedirect } from "../src/index.js";

const SECRET = "x".repeat(40);
const env = { TOKEN_SECRET: SECRET, DEMO_PROVIDER: "on", STRIPE_SECRET_KEY: "sk_test_123" };
const leg = (i, mode = "BUS") => ({
  index: i, mode, operator: "Flix", line: "N1",
  from: { name: `A${i}`, lat: 48.2, lon: 16.37, tz: "Europe/Vienna" },
  to: { name: `B${i}`, lat: 48.3, lon: 16.5, tz: "Europe/Vienna" },
  departure: "2026-12-01T08:00:00Z", arrival: "2026-12-01T09:00:00Z",
});
const customer = { firstName: "Ana", lastName: "Muster", email: "ana@example.org" };

function fakeStripe() {
  const calls = [];
  let intent = null;
  return {
    calls,
    setIntent(value) { intent = value; },
    async createCheckout(params) {
      calls.push(["create", params]);
      intent = { id: "pi_1", status: "requires_capture", metadata: { ...params.payment_intent_data.metadata } };
      return { id: "cs_test_abcdefgh", url: "https://checkout.stripe.com/c/pay/cs_test_abcdefgh" };
    },
    async session() { return { id: "cs_test_abcdefgh", currency: "eur", payment_intent: intent }; },
    async capture(id, amount) { calls.push(["capture", amount]); intent = { ...intent, status: "succeeded" }; return {}; },
    async cancel() { calls.push(["cancel"]); intent = { ...intent, status: "canceled" }; return {}; },
    async setMetadata(id, metadata) { intent = { ...intent, metadata: { ...intent.metadata, ...metadata } }; return {}; },
  };
}

test("tokens reject tampering and expiry", async () => {
  const token = await sign({ p: "demo", amount: 100 }, SECRET, 60, 1_000_000);
  assert.deepEqual((await verify(token, SECRET, 1_000_000)).amount, 100);
  const [body, mac] = token.split(".");
  const forged = Buffer.from(JSON.stringify({ p: "demo", amount: 1, exp: 9e9 })).toString("base64url");
  assert.equal(await verify(`${forged}.${mac}`, SECRET, 1_000_000), null);
  assert.equal(await verify(`${body}.${mac}`, SECRET, 1_000_000 + 61_000), null);
  assert.equal(await verify(token, "y".repeat(40), 1_000_000), null);
});

test("offer request is validated", () => {
  assert.throws(() => parseOfferRequest({ legs: [] }), ShopError);
  assert.throws(() => parseOfferRequest({ legs: [{ ...leg(0), departure: "tomorrow" }] }), ShopError);
  assert.throws(() => parseOfferRequest({ legs: [leg(0)], adults: 20 }), ShopError);
  assert.equal(parseOfferRequest({ legs: [leg(0)] }).currency, "EUR");
});

test("walking legs get no offer, transit legs do", async () => {
  const result = await findOffers({ legs: [leg(0), leg(1, "WALK"), leg(2, "TRAM")] }, env);
  assert.deepEqual(result.offers.map((o) => o.leg), [0, 2]);
  assert.ok(result.offers.every((o) => o.provider === "demo" && o.amount > 0 && o.token));
});

test("demo provider stays off with live Stripe keys", async () => {
  const result = await findOffers({ legs: [leg(0)] }, { ...env, STRIPE_SECRET_KEY: "sk_live_x" });
  assert.equal(result.offers.length, 0);
});

test("one checkout for all legs, captured after booking, tickets returned", async () => {
  const { offers } = await findOffers({ legs: [leg(0), leg(1)] }, env);
  const stripe = fakeStripe();
  const order = await checkout({ offers: offers.map((o) => o.token), customer, termsAccepted: true }, env,
    { stripe, origin: "https://shop.example" });
  assert.equal(order.order, "cs_test_abcdefgh");
  assert.equal(order.amount, offers[0].amount + offers[1].amount);
  const params = stripe.calls[0][1];
  assert.equal(params.payment_intent_data.capture_method, "manual");
  assert.equal(params.line_items.length, 2);
  assert.match(params.success_url, /^https:\/\/shop\.example\/v1\/return\?session_id=/);

  const done = await complete("cs_test_abcdefgh", env, { stripe });
  assert.equal(done.status, "booked");
  assert.deepEqual(stripe.calls.find((c) => c[0] === "capture"), ["capture", order.amount]);
  assert.equal(done.items[0].tickets[0].origin, "A0");
  assert.equal(done.items[0].tickets[0].passenger, "Ana Muster");
  assert.equal(done.items[0].tickets[0].barcode.format, "qr");

  // Repeating the call (app restarted) returns the tickets again without charging twice.
  const again = await complete("cs_test_abcdefgh", env, { stripe });
  assert.equal(again.status, "booked");
  assert.equal(stripe.calls.filter((c) => c[0] === "capture").length, 1);
});

test("a leg that fails after payment is not charged", async () => {
  const { offers } = await findOffers({ legs: [leg(0), leg(1)] }, env);
  const stripe = fakeStripe();
  const order = await checkout({ offers: offers.map((o) => o.token), customer, termsAccepted: true }, env,
    { stripe, origin: "https://shop.example" });
  const { demo } = await import("../src/providers/demo.js");
  const original = demo.confirm;
  let n = 0;
  demo.confirm = async (ref) => { if (n++ === 1) throw new Error("sold out"); return original(ref); };
  try {
    const done = await complete(order.order, env, { stripe });
    assert.equal(done.status, "partial");
    assert.deepEqual(stripe.calls.find((c) => c[0] === "capture"), ["capture", offers[0].amount]);
    assert.equal(done.amountCharged, offers[0].amount);
  } finally {
    demo.confirm = original;
  }
});

test("checkout needs accepted terms, a name and valid offers", async () => {
  const stripe = fakeStripe();
  await assert.rejects(checkout({ offers: ["x"], customer, termsAccepted: false }, env, { stripe }), /Terms/);
  await assert.rejects(checkout({ offers: ["x"], customer: { email: "a@b.c" }, termsAccepted: true }, env, { stripe }), /Name/);
  await assert.rejects(checkout({ offers: ["x.y"], customer, termsAccepted: true }, env, { stripe }), /expired/);
});

test("unpaid or cancelled orders return no tickets", async () => {
  const stripe = fakeStripe();
  stripe.setIntent({ id: "pi_1", status: "requires_payment_method", metadata: {} });
  await assert.rejects(complete("cs_test_abcdefgh", env, { stripe }), /Not paid/);
  stripe.setIntent({ id: "pi_1", status: "canceled", metadata: {} });
  await assert.rejects(complete("cs_test_abcdefgh", env, { stripe }), /cancelled/);
  await assert.rejects(complete("../etc", env, { stripe }), /Unknown order/);
});

test("Stripe return goes back to the app", () => {
  const ok = returnRedirect(new URL("https://shop.example/v1/return?session_id=cs_test_abcdefgh"));
  assert.equal(ok.headers.get("Location"), "publit://shop/return?order=cs_test_abcdefgh");
  const bad = returnRedirect(new URL("https://shop.example/v1/return?session_id=javascript:alert(1)"));
  assert.equal(bad.headers.get("Location"), "publit://shop/return?cancelled=1");
});

test("worker answers offers and refuses unknown routes", async () => {
  const response = await worker.fetch(new Request("https://shop.example/v1/offers", {
    method: "POST", body: JSON.stringify({ legs: [leg(0)] }) }), env);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).offers.length, 1);
  assert.equal((await worker.fetch(new Request("https://shop.example/admin", { method: "POST" }), env)).status, 404);
  assert.equal((await worker.fetch(new Request("https://shop.example/v1/offers", { method: "POST", body: "{" }), env)).status, 400);
});

test("Stripe form encoding nests objects and arrays", () => {
  const encoded = form({ line_items: [{ price_data: { unit_amount: 5 } }], mode: "payment" }).toString();
  assert.equal(decodeURIComponent(encoded), "line_items[0][price_data][unit_amount]=5&mode=payment");
});

test("Distribusion: local station times become instants", () => {
  assert.equal(_test.instant("2026-12-01T09:00", "Europe/Vienna"), "2026-12-01T08:00:00.000Z");
  assert.equal(_test.instant("2026-07-01T09:00", "Europe/Vienna"), "2026-07-01T07:00:00.000Z");
  assert.equal(_test.localDate("2026-12-01T23:30:00Z", "Europe/Vienna"), "2026-12-02");
});

test("Distribusion: picks the connection that is this leg, cheapest fare", async () => {
  const response = {
    meta: { currency: "EUR", locale: "en" },
    data: [
      { id: "c1", type: "connections", attributes: { departure_time: "2026-12-01T07:00", arrival_time: "2026-12-01T08:00" },
        relationships: { departure_station: { data: { id: "S1" } }, arrival_station: { data: { id: "S2" } },
          marketing_carrier: { data: { id: "FLIX" } }, fares: { data: [{ id: "f0" }] } } },
      { id: "c2", type: "connections", attributes: { departure_time: "2026-12-01T09:01", arrival_time: "2026-12-01T10:00" },
        relationships: { departure_station: { data: { id: "S1" } }, arrival_station: { data: { id: "S2" } },
          marketing_carrier: { data: { id: "FLIX" } }, fares: { data: [{ id: "f1" }, { id: "f2" }] } } },
    ],
    included: [
      { type: "stations", id: "S1", attributes: { code: "ATVIEVIE", name: "Wien", time_zone: "Europe/Vienna" } },
      { type: "stations", id: "S2", attributes: { code: "ATVIEAIR", name: "Flughafen", time_zone: "Europe/Vienna" } },
      { type: "marketing_carriers", id: "FLIX", attributes: { code: "FLIX", trade_name: "FlixBus" } },
      { type: "fares", id: "f0", attributes: { price: 100, offer_id: "o0" } },
      { type: "fares", id: "f1", attributes: { price: 1299, offer_id: "o1" }, relationships: { fare_class: { data: { id: "FC1" } } } },
      { type: "fares", id: "f2", attributes: { price: 899, offer_id: "o2" }, relationships: { fare_class: { data: { id: "FC2" } } } },
      { type: "fare_classes", id: "FC2", attributes: { code: "FARE-2", name: "Basic" } },
    ],
  };
  let sent;
  const fetchImpl = async (url, init) => { sent = { url, body: JSON.parse(init.body), key: init.headers["Api-Key"] };
    return new Response(JSON.stringify(response), { status: 200 }); };
  const offers = await distribusion.offers(leg(0), { adults: 1, currency: "EUR", locale: "de" }, { DISTRIBUSION_API_KEY: "k" }, fetchImpl);
  assert.equal(sent.key, "k");
  assert.match(sent.url, /\/connections\/find$/);
  assert.equal(sent.body.search_bounds[0].departure_location.type, "geo");
  assert.equal(offers.length, 1);
  assert.equal(offers[0].amount, 899);
  assert.equal(offers[0].operator, "FlixBus");
  assert.equal(offers[0].data.offerId, "o2");
  assert.equal(offers[0].data.fareClass, "FARE-2");
  assert.equal(offers[0].data.from, "ATVIEVIE");
});

test("Distribusion is off without an API key and only sells long-distance modes", () => {
  assert.equal(distribusion.enabled({}), false);
  assert.equal(distribusion.covers({ mode: "TRAM" }), false);
  assert.equal(distribusion.covers({ mode: "LONG_DISTANCE" }), true);
});

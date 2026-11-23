// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import test from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";
import { demoPayments, demoPaymentsActive } from "../src/demopay.js";

const env = { TOKEN_SECRET: "x".repeat(40), DEMO_PROVIDER: "on", DEMO_PAYMENTS: "on" };
const leg = { index: 0, mode: "BUS", operator: "Flix", line: "N1",
  from: { name: "Wien", lat: 48.2, lon: 16.37, tz: "Europe/Vienna" }, to: { name: "Graz", lat: 47.07, lon: 15.44, tz: "Europe/Vienna" },
  departure: "2026-12-01T08:00:00Z", arrival: "2026-12-01T10:30:00Z" };
const post = (path, body) => new Request(`https://shop.example${path}`, { method: "POST", body: JSON.stringify(body) });

test("demo payments only without Stripe and real sellers", () => {
  assert.equal(demoPaymentsActive(env), true);
  assert.equal(demoPaymentsActive({ ...env, STRIPE_SECRET_KEY: "sk_test_1" }), false);
  assert.equal(demoPaymentsActive({ ...env, DISTRIBUSION_API_KEY: "k" }), false);
  assert.equal(demoPaymentsActive({ ...env, DEMO_PROVIDER: "off" }), false);
  assert.equal(demoPaymentsActive({ ...env, DEMO_PAYMENTS: "off" }), false);
});

test("whole purchase with the demo payment page", async () => {
  const demoPay = demoPayments();
  const call = (req) => worker.fetch(req, env, {}, { demoPay });
  const offers = await (await call(post("/v1/offers", { legs: [leg] }))).json();
  assert.equal(offers.offers.length, 1);
  const order = await (await call(post("/v1/checkout", { offers: [offers.offers[0].token], termsAccepted: true,
    customer: { firstName: "Ana", lastName: "Muster", email: "ana@example.org" } }))).json();
  assert.match(order.order, /^cs_demo_/);

  // Not paid yet.
  assert.equal((await (await call(post(`/v1/orders/${order.order}/complete`, {}))).json()).error, "unpaid");

  const page = await call(new Request(order.paymentURL));
  assert.match(await page.text(), /Demo: Es wird nichts abgebucht/);
  const paid = await call(new Request(order.paymentURL, { method: "POST", body: "action=pay",
    headers: { "Content-Type": "application/x-www-form-urlencoded" } }));
  assert.equal(paid.status, 303);
  assert.equal(paid.headers.get("location"), `https://shop.example/v1/return?session_id=${order.order}`);

  const done = await (await call(post(`/v1/orders/${order.order}/complete`, {}))).json();
  assert.equal(done.status, "booked");
  assert.equal(done.items[0].tickets[0].passenger, "Ana Muster");
});

test("cancelling on the demo page returns as cancelled", async () => {
  const demoPay = demoPayments();
  const session = await demoPay.createCheckout({ line_items: [{ quantity: 1, price_data: { currency: "eur", unit_amount: 500 } }],
    success_url: "https://s.example/v1/return?session_id={CHECKOUT_SESSION_ID}", cancel_url: "https://s.example/v1/return?cancelled=1" });
  const res = await demoPay.page(new Request(session.url, { method: "POST", body: "action=cancel" }));
  assert.equal(res.headers.get("location"), "https://s.example/v1/return?cancelled=1");
});

test("demo page is off when demo payments are off", async () => {
  const res = await worker.fetch(new Request("https://shop.example/v1/demo-pay?session=cs_demo_1"), { TOKEN_SECRET: "x".repeat(40) }, {});
  assert.equal(res.status, 404);
});

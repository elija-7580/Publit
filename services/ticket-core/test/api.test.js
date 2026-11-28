// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import test from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../src/app.js";
import { createStore } from "../src/store.js";
import { generateKeyPair, signTicket, present, deviceKeyFromJwk, parseTicket } from "../src/core/token.js";
import { openTrustList, checkTicket } from "../src/core/validate.js";
import { b64u, encoder } from "../src/core/bytes.js";
import { createHmac } from "node:crypto";
import { decodeUic918 } from "../src/formats/uic918.js";

function setup({ demo = false, start = Date.parse("2026-12-01T08:00:00Z"), fetch, secretsKey = "a-long-test-key-for-the-vault-0123" } = {}) {
  const clock = { now: start };
  const store = createStore();
  const app = createApp({ store, env: { DEMO: demo ? "on" : "off", ADMIN_TOKEN: "admin-secret", DEMO_PAYMENTS: "on", SECRETS_KEY: secretsKey }, now: () => clock.now, fetch });
  const call = async (method, path, body, key) => {
    const response = await app(new Request(`http://core${path}`, {
      method, headers: { "content-type": "application/json", ...(key ? { authorization: `Bearer ${key}` } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    }));
    return { status: response.status, body: await response.json() };
  };
  return { clock, store, app, call };
}

async function onboard(call, extra = {}) {
  const applied = await call("POST", "/v1/operators/apply", { name: "Seebus Linien", country: "at", contactEmail: "office@seebus.example", level: "hosted", ...extra });
  assert.equal(applied.status, 201);
  const approved = await call("POST", `/v1/admin/operators/${applied.body.operator.id}/approve`, {}, "admin-secret");
  assert.equal(approved.status, 200);
  return { id: applied.body.operator.id, key: applied.body.apiKey };
}

// What a conductor's device does: load the list once, verify it against the root key, then check offline.
async function offlineTrust(call) {
  const root = (await call("GET", "/v1/trust/root")).body;
  const trust = await openTrustList((await call("GET", "/v1/trust")).body, root.jwk);
  assert.ok(trust, "trust list verifies against the root key");
  return trust;
}

async function buy(call, productId, extra = {}) {
  const order = await call("POST", "/v1/orders", { productId, ...extra });
  assert.equal(order.status, 201, JSON.stringify(order.body));
  const paid = await call("POST", `/v1/orders/${order.body.order.id}/pay`, { secret: order.body.order.secret });
  assert.equal(paid.status, 200, JSON.stringify(paid.body));
  return { order: order.body.order, ticket: paid.body.ticket };
}

test("onboarding: apply, wait for approval, then publish a product", async () => {
  const { call } = setup();
  const applied = await call("POST", "/v1/operators/apply", { name: "Seebus Linien", country: "AT", contactEmail: "office@seebus.example" });
  assert.equal(applied.body.operator.status, "pending");
  assert.match(applied.body.apiKey, /^ptc_/);
  const key = applied.body.apiKey;
  const product = { name: "Tageskarte", template: "day", price: { amount: 900, currency: "EUR" } };
  assert.equal((await call("POST", "/v1/operator/products", product, key)).status, 403);
  assert.equal((await call("POST", "/v1/admin/operators/seebus-linien/approve", {}, "wrong")).status, 401);
  assert.equal((await call("POST", "/v1/admin/operators/seebus-linien/approve", {}, "admin-secret")).body.operator.status, "active");
  const created = await call("POST", "/v1/operator/products", product, key);
  assert.equal(created.status, 201);
  assert.equal(created.body.product.id, "seebus-linien.tageskarte");
  assert.deepEqual(created.body.product.validity.operators, ["seebus-linien"]);
  assert.equal(created.body.product.description.de.duration, "bis Betriebsschluss des Tages");
  // The same name cannot be taken twice, and nobody gets in without a key.
  assert.equal((await call("POST", "/v1/operators/apply", { name: "Seebus Linien", country: "AT", contactEmail: "x@y.example" })).status, 409);
  assert.equal((await call("GET", "/v1/operator")).status, 401);
  assert.equal((await call("GET", "/v1/operator", undefined, "ptc_nope")).status, 401);
  const listed = await call("GET", "/v1/operators");
  assert.equal(listed.body.operators[0].keys[0].hosted, true);
  assert.equal(JSON.stringify(listed.body).includes('"d"'), false, "no private key leaves the server");
});

test("onboarding: bad applications are refused", async () => {
  const { call } = setup();
  for (const body of [{ country: "AT", contactEmail: "a@b.example" }, { name: "X Bus", country: "Austria", contactEmail: "a@b.example" },
    { name: "X Bus", country: "AT", contactEmail: "nope" }, { name: "X Bus", country: "AT", contactEmail: "a@b.example", level: "magic" },
    { name: "X Bus", country: "AT", contactEmail: "a@b.example", level: "own-keys" }]) {
    assert.equal((await call("POST", "/v1/operators/apply", body)).status, 400, JSON.stringify(body));
  }
  assert.equal((await call("POST", "/v1/operators/apply", "[]")).status, 400);
});

test("a ticket is bought, checked offline, and refused once it is refunded", async () => {
  const { call, clock } = setup();
  const operator = await onboard(call);
  await call("POST", "/v1/operator/products", { name: "24 Stunden", template: "hours", params: { hours: 24 }, price: { amount: 1000, currency: "EUR" } }, operator.key);
  const { ticket, order } = await buy(call, "seebus-linien.24-stunden", { travellers: 2 });
  assert.equal(ticket.amount, 2000);
  assert.equal(ticket.validUntil, "2026-12-02T08:00:00.000Z");
  assert.equal(ticket.description.de.when, "Gilt ab 01.12.2026, 09:00 bis 02.12.2026, 09:00 (Europe/Vienna)");
  // Paying twice gives the same ticket, and the order can be fetched again with its secret only.
  const again = await call("POST", `/v1/orders/${order.id}/pay`, { secret: order.secret });
  assert.equal(again.body.ticket.id, ticket.id);
  assert.equal((await call("GET", `/v1/orders/${order.id}?secret=${order.secret}`)).body.ticket.token, ticket.token);
  assert.equal((await call("GET", `/v1/orders/${order.id}?secret=wrong`)).status, 404);

  const trust = await offlineTrust(call);
  const onBus = { agencyName: "Seebus Linien", mode: "BUS", line: "7" };
  const ok = await checkTicket(ticket.token, trust, { now: clock.now + 3600000, context: onBus });
  assert.deepEqual([ok.level, ok.code], ["valid", "valid"]);
  assert.equal((await checkTicket(ticket.token, trust, { now: clock.now + 3600000, context: { agencyName: "Other Bus", mode: "BUS" } })).level, "check");
  assert.equal((await checkTicket(ticket.token, trust, { now: clock.now + 25 * 3600000 })).code, "expired");
  assert.equal((await checkTicket(ticket.token, trust, { now: clock.now - 3600000 })).code, "not_yet_valid");

  // Forgery: the same ticket with a later end.
  const parsed = parseTicket(ticket.token);
  const forged = `PT1.${b64u(encoder.encode(JSON.stringify({ ...parsed.payload, exp: parsed.payload.exp + 86400 })))}.${parsed.signature}`;
  assert.equal((await checkTicket(forged, trust, { now: clock.now })).code, "signature_bad");
  // A ticket signed by a key nobody registered.
  const stranger = await generateKeyPair();
  assert.equal((await checkTicket(await signTicket(parsed.payload, stranger.privateJwk), trust, { now: clock.now })).code, "signature_bad");
  assert.equal((await checkTicket(await signTicket({ ...parsed.payload, iss: "nobody" }, stranger.privateJwk), trust, { now: clock.now })).code, "unknown_issuer");
  // A trust list that was changed on the way does not open.
  const signed = (await call("GET", "/v1/trust")).body;
  assert.equal(await openTrustList({ ...signed, list: signed.list.replace("seebus", "seebux") }, (await call("GET", "/v1/trust/root")).body.jwk), null);

  // The online check says the same and adds the scope in words.
  const online = await call("POST", "/v1/validate", { code: ticket.token, context: onBus });
  assert.equal(online.body.level, "valid");
  assert.equal(online.body.description.en.operators, "Seebus Linien");

  // Refund: only the issuing operator may, and the next trust list carries it.
  assert.equal((await call("POST", `/v1/operator/tickets/${ticket.id}/revoke`, {}, "ptc_other")).status, 401);
  assert.equal((await call("POST", `/v1/operator/tickets/${ticket.id}/revoke`, { reason: "refund" }, operator.key)).body.ticket.status, "revoked");
  assert.equal((await checkTicket(ticket.token, trust, { now: clock.now })).level, "valid", "a device that has not synced still accepts it");
  assert.equal((await checkTicket(ticket.token, await offlineTrust(call), { now: clock.now })).code, "revoked");
  const statement = (await call("GET", "/v1/operator/statement", undefined, operator.key)).body;
  assert.deepEqual([statement.total.tickets, statement.total.refunded, statement.total.gross], [0, 1, 0]);
});

test("a live ticket only passes when the buyer's device shows it now", async () => {
  const { call, clock } = setup();
  const operator = await onboard(call);
  await call("POST", "/v1/operator/products", { name: "Einzelfahrt", template: "single", price: { amount: 300, currency: "EUR" } }, operator.key);
  const device = await generateKeyPair();
  const { ticket } = await buy(call, "seebus-linien.einzelfahrt", { deviceKey: deviceKeyFromJwk(device.publicJwk) });
  assert.equal(ticket.live, true);
  const trust = await offlineTrust(call);
  const seconds = Math.floor(clock.now / 1000);
  assert.equal((await checkTicket(await present(ticket.token, device.privateJwk, seconds + 5), trust, { now: clock.now + 10000 })).level, "valid");
  assert.equal((await checkTicket(ticket.token, trust, { now: clock.now })).code, "live_missing");
  // A screenshot taken five minutes ago.
  assert.equal((await checkTicket(await present(ticket.token, device.privateJwk, seconds), trust, { now: clock.now + 300000 })).code, "live_stale");
  const thief = await generateKeyPair();
  assert.equal((await checkTicket(await present(ticket.token, thief.privateJwk, seconds), trust, { now: clock.now })).code, "live_bad");
  assert.equal((await call("POST", "/v1/orders", { productId: "seebus-linien.einzelfahrt", deviceKey: "short" })).status, 400);
});

test("a ticket keeps the scope it was sold under when the product changes", async () => {
  const { call, clock } = setup();
  const operator = await onboard(call);
  const zone = (stops) => [{ type: "zone", id: "a", name: "Zone A", stops }];
  const v1 = await call("POST", "/v1/operator/products", { name: "Zonenticket", template: "hours", price: { amount: 500, currency: "EUR" }, area: zone(["s1", "s2"]) }, operator.key);
  const { ticket } = await buy(call, "seebus-linien.zonenticket");
  const v2 = await call("POST", "/v1/operator/products", { name: "Zonenticket", template: "hours", price: { amount: 600, currency: "EUR" }, area: zone(["s1"]) }, operator.key);
  assert.deepEqual([v1.body.product.version, v2.body.product.version], [1, 2]);
  assert.notEqual(v1.body.product.hash, v2.body.product.hash);
  assert.equal((await call("GET", "/v1/products/seebus-linien.zonenticket")).body.product.price.amount, 600);
  const trust = await offlineTrust(call);
  const at = (id) => ({ agencyName: "Seebus Linien", mode: "BUS", stop: { stopId: id } });
  assert.equal((await checkTicket(ticket.token, trust, { now: clock.now, context: at("s2") })).level, "valid", "the old ticket still covers s2");
  assert.equal((await checkTicket(ticket.token, trust, { now: clock.now, context: { agencyName: "Seebus Linien", mode: "BUS" } })).level, "valid", "no stop known: the area is left open");
  const fresh = await buy(call, "seebus-linien.zonenticket");
  assert.equal((await checkTicket(fresh.ticket.token, trust, { now: clock.now, context: at("s2") })).code, "scope_area");
  const mine = (await call("GET", "/v1/operator/products", undefined, operator.key)).body.products[0];
  assert.deepEqual(mine.versions.map((v) => v.status), ["replaced", "published"]);
  assert.equal((await call("POST", "/v1/operator/products/seebus-linien.zonenticket/retire", {}, operator.key)).status, 200);
  assert.equal((await call("POST", "/v1/orders", { productId: "seebus-linien.zonenticket" })).status, 404);
  assert.equal((await checkTicket(ticket.token, await offlineTrust(call), { now: clock.now, context: at("s1") })).level, "valid", "retiring does not void sold tickets");
});

test("key change keeps old tickets alive, a stolen key voids them, a suspended operator is refused", async () => {
  const { call, clock } = setup();
  const operator = await onboard(call);
  await call("POST", "/v1/operator/products", { name: "Tageskarte", template: "day", price: { amount: 900, currency: "EUR" } }, operator.key);
  const first = await buy(call, "seebus-linien.tageskarte");
  clock.now += 60000;
  assert.equal((await call("POST", "/v1/operator/keys", {}, operator.key)).body.operator.keys.length, 2);
  const second = await buy(call, "seebus-linien.tageskarte");
  assert.notEqual(parseTicket(first.ticket.token).payload.kid, parseTicket(second.ticket.token).payload.kid);
  let trust = await offlineTrust(call);
  assert.equal((await checkTicket(first.ticket.token, trust, { now: clock.now })).level, "valid");
  assert.equal((await checkTicket(second.ticket.token, trust, { now: clock.now })).level, "valid");
  clock.now += 60000;
  await call("POST", "/v1/operator/keys", { compromised: true }, operator.key);
  trust = await offlineTrust(call);
  assert.equal((await checkTicket(second.ticket.token, trust, { now: clock.now })).code, "key_not_valid");
  assert.equal((await checkTicket(first.ticket.token, trust, { now: clock.now })).level, "valid");
  await call("POST", `/v1/admin/operators/${operator.id}/suspend`, {}, "admin-secret");
  assert.equal((await checkTicket(first.ticket.token, await offlineTrust(call), { now: clock.now })).code, "issuer_suspended");
  assert.equal((await call("POST", "/v1/orders", { productId: "seebus-linien.tageskarte" })).status, 409);
});

test("an operator with its own keys signs its tickets itself and passes the same check", async () => {
  const { call, clock } = setup();
  const own = await generateKeyPair();
  const operator = await onboard(call, { name: "Talbahn", level: "own-keys", publicKeyJwk: own.publicJwk });
  const product = (await call("POST", "/v1/operator/products", { name: "Netzkarte", template: "month", price: { amount: 4900, currency: "EUR" } }, operator.key)).body.product;
  const seconds = Math.floor(clock.now / 1000);
  const token = await signTicket({ v: 1, id: "TOWN000001", iss: "talbahn", kid: "talbahn-1", p: product.id, pv: 1, vh: product.hash, nbf: seconds, exp: seconds + 3600, iat: seconds, n: 1 }, own.privateJwk);
  const trust = await offlineTrust(call);
  assert.equal((await checkTicket(token, trust, { now: clock.now, context: { agencyName: "Talbahn", mode: "REGIONAL_RAIL" } })).level, "valid");
  // It cannot issue another operator's product, nor change the scope behind the hash.
  const seebus = await onboard(call);
  const other = (await call("POST", "/v1/operator/products", { name: "Tageskarte", template: "day", price: { amount: 900, currency: "EUR" } }, seebus.key)).body.product;
  const stolen = await signTicket({ v: 1, id: "TOWN000002", iss: "talbahn", kid: "talbahn-1", p: other.id, pv: 1, vh: other.hash, nbf: seconds, exp: seconds + 3600, iat: seconds }, own.privateJwk);
  assert.equal((await checkTicket(stolen, await offlineTrust(call), { now: clock.now })).code, "product_unknown");
  // Publit holds no key for it, so it cannot sell on its behalf.
  assert.equal((await call("POST", "/v1/orders", { productId: product.id })).status, 409);
  assert.equal((await call("POST", "/v1/operator/keys", { publicKeyJwk: own.privateJwk }, operator.key)).status, 400, "a private key is never accepted");
});

test("tickets between two stops and personal passes ask for what they need", async () => {
  const { call, clock } = setup();
  const operator = await onboard(call);
  await call("POST", "/v1/operator/products", { name: "Einzelfahrt", template: "single_route", price: { amount: 480, currency: "EUR" }, start: "chosen" }, operator.key);
  await call("POST", "/v1/operator/products", { name: "Jahreskarte", template: "year", price: { amount: 36500, currency: "EUR" } }, operator.key);
  assert.equal((await call("POST", "/v1/orders", { productId: "seebus-linien.einzelfahrt" })).status, 400);
  const od = { from: { id: "a", name: "Seedorf" }, to: { id: "b", name: "Bergheim" } };
  const { ticket } = await buy(call, "seebus-linien.einzelfahrt", { od, start: "2026-12-03T10:00:00Z" });
  assert.equal(ticket.validFrom, "2026-12-03T10:00:00.000Z");
  assert.deepEqual(ticket.description.de.where, ["Strecke Seedorf – Bergheim"]);
  const trust = await offlineTrust(call);
  const later = Date.parse("2026-12-03T10:30:00Z");
  const at = (stop) => ({ agencyName: "Seebus Linien", mode: "BUS", stop });
  assert.equal((await checkTicket(ticket.token, trust, { now: later, context: at({ stopId: "a" }) })).level, "valid");
  assert.equal((await checkTicket(ticket.token, trust, { now: later, context: at({ stopId: "zz", name: "Mitte" }) })).code, "scope_route_between");
  assert.equal((await checkTicket(ticket.token, trust, { now: clock.now })).code, "not_yet_valid");

  assert.equal((await call("POST", "/v1/orders", { productId: "seebus-linien.jahreskarte" })).status, 400);
  const pass = await buy(call, "seebus-linien.jahreskarte", { holder: { name: "Erika Musterfrau", birthYear: 1990 } });
  const checked = await checkTicket(pass.ticket.token, trust, { now: clock.now });
  assert.deepEqual([checked.level, checked.code, checked.ticket.hn], ["check", "check_id", "Erika Musterfrau"]);
  assert.equal(pass.ticket.validUntil, "2027-11-30T22:59:59.000Z");
});

test("inspections are counted, the statement shows sales minus commission", async () => {
  const { call } = setup();
  const operator = await onboard(call, { commissionBps: 700 });
  await call("POST", "/v1/operator/products", { name: "Tageskarte", template: "day", price: { amount: 1000, currency: "EUR" } }, operator.key);
  const a = await buy(call, "seebus-linien.tageskarte");
  await buy(call, "seebus-linien.tageskarte", { travellers: 3 });
  const statement = (await call("GET", "/v1/operator/statement", undefined, operator.key)).body;
  assert.deepEqual(statement.total, { tickets: 2, refunded: 0, gross: 4000, commission: 280, net: 3720, currency: "EUR" });
  const event = { ticketId: a.ticket.id, result: "valid", line: "7" };
  await call("POST", "/v1/operator/inspections", { events: [{ ...event, device: "d1" }] }, operator.key);
  const seen = await call("POST", "/v1/operator/inspections", { events: [{ ...event, device: "d2" }] }, operator.key);
  assert.deepEqual(seen.body.results, [{ ticketId: a.ticket.id, seenBefore: 1, otherDevices: 1 }]);
});

test("GTFS fares become drafts that the operator reviews and publishes", async () => {
  const { call } = setup();
  const operator = await onboard(call);
  const files = {
    "fare_products.txt": "fare_product_id,fare_product_name,amount,currency\nsingle_core,Einzelfahrt Kernzone,2.60,EUR\nday_all,\"Tageskarte, alle Zonen\",8.50,EUR\nbroken,,x,EUR\n",
    "fare_leg_rules.txt": "leg_group_id,from_area_id,to_area_id,fare_product_id\ng,core,core,single_core\ng,,,day_all\n",
    "areas.txt": "area_id,area_name\ncore,Kernzone\n",
    "stop_areas.txt": "area_id,stop_id\ncore,s1\ncore,s2\n",
    "fare_transfer_rules.txt": "from_leg_group_id,to_leg_group_id,duration_limit,fare_transfer_type\ng,g,3600,0\n",
  };
  const imported = await call("POST", "/v1/operator/import/gtfs-fares", { files }, operator.key);
  assert.equal(imported.status, 201);
  assert.deepEqual(imported.body.drafts.map((d) => [d.id, d.price.amount]), [["seebus-linien.single-core", 260], ["seebus-linien.day-all", 850]]);
  assert.match(imported.body.drafts[0].review[0], /60 minutes/);
  assert.equal((await call("GET", "/v1/products")).body.products.length, 0, "drafts are not on sale");
  const published = await call("POST", "/v1/operator/products/seebus-linien.single-core/publish", {}, operator.key);
  assert.deepEqual(published.body.product.validity.area, [{ type: "zone", id: "core", name: "Kernzone", stops: ["s1", "s2"] }]);
  assert.deepEqual(published.body.product.validity.time, { type: "duration", minutes: 60 });
  assert.equal((await call("GET", "/v1/products?sellable=1")).body.products.length, 1);
  assert.equal((await call("POST", "/v1/operator/import/gtfs-fares", { files: {} }, operator.key)).status, 400);
});

test("demo: a photographed ticket is recognised and only the rides it covers are offered", async () => {
  const { call, clock } = setup({ demo: true, start: Date.parse("2026-11-28T13:00:00Z") });
  const klima = (await call("POST", "/v1/recognize", { text: "KlimaTicket Ö\nErika Musterfrau\nGültig ab 01.03.2026 bis 28.02.2027" })).body.candidates;
  assert.equal(klima[0].productId, "klimaticket.oesterreich");
  assert.deepEqual([klima[0].entitlement.validFrom, klima[0].entitlement.validUntil, klima[0].assumed], ["2026-02-28T23:00:00.000Z", "2027-02-28T22:59:59.000Z", []]);
  assert.equal(klima[0].approximate, true);
  // OCR is never clean: a wrong letter and no accents still find it.
  assert.equal((await call("POST", "/v1/recognize", { text: "K1imaTicket O gultig bis 28.02.2027" })).body.candidates[0]?.productId, "klimaticket.oesterreich");
  assert.deepEqual((await call("POST", "/v1/recognize", { text: "Kassenbon Bäckerei 3,20 EUR" })).body.candidates, []);

  const day = (await call("POST", "/v1/recognize", { text: "WIENER LINIEN\n24 Stunden Wien\nentwertet 28.11.2026 13:30" })).body.candidates[0];
  assert.deepEqual([day.productId, day.entitlement.validFrom, day.entitlement.validUntil, day.assumed], ["wiener-linien.24-stunden-wien", "2026-11-28T12:30:00.000Z", "2026-11-29T12:30:00.000Z", ["until"]]);
  assert.equal((await call("POST", "/v1/recognize", { text: "72 Stunden Wien Wiener Linien" })).body.candidates[0].productId, "wiener-linien.72-stunden-wien");

  const journeys = async (from, to) => (await call("GET", `/v1/demo/journeys?from=${from}&to=${to}`)).body.journeys;
  const cover = async (entitlement, from, to, only) => (await call("POST", "/v1/coverage", { entitlements: [entitlement], journeys: await journeys(from, to), only })).body;
  // KlimaTicket: rail to Salzburg yes, the coach no.
  const toSalzburg = await cover(klima[0].entitlement, "wien", "salzburg");
  assert.deepEqual(toSalzburg.journeys.map((j) => j.coverage.status), ["full", "full", "partial"]);
  assert.equal(toSalzburg.journeys[2].coverage.legs[1].text.de, "Verkehrsmittel nicht enthalten");
  assert.equal((await cover(klima[0].entitlement, "wien", "salzburg", "full")).journeys.length, 2);
  assert.equal(toSalzburg.entitlements[0].routerModes.includes("COACH"), false);
  // It ends at the border.
  assert.equal((await cover(klima[0].entitlement, "wien", "muenchen")).journeys[0].coverage.legs[1].text.en, "Outside the area of validity: München Hauptbahnhof");
  // The Vienna day ticket: underground yes, the S-Bahn to the airport leaves the zone, the airport train is excluded.
  const toAirport = await cover(day.entitlement, "wien", "flughafen");
  assert.deepEqual(toAirport.journeys.map((j) => j.coverage.legs.at(-1).reason), ["area", "excepted", "excepted"]);
  assert.equal(toAirport.journeys[0].coverage.approximate, true);
  // Deutschlandticket: the regional train from Salzburg, not the Railjet.
  const dticket = (await call("POST", "/v1/recognize", { text: "Deutschlandticket\nMax Mustermann" })).body.candidates[0];
  assert.deepEqual((await cover(dticket.entitlement, "salzburg", "muenchen")).journeys.map((j) => j.coverage.status), ["full", "none", "none"]);

  // No ticket at all: the platform offers what it sells for each ride.
  const plain = (await call("POST", "/v1/coverage", { journeys: await journeys("salzburg", "fuschl") })).body.journeys;
  assert.equal(plain[0].coverage.legs[0].offer.productId, "alpenland-bus.einzelfahrt");
  assert.deepEqual(plain[0].coverage.extra, { amount: 480, currency: "EUR" });
  assert.equal(plain[1].coverage.legs[0].offer, null);

  // A ticket bought here is exact and verified, also when it comes back as a scanned code.
  const { ticket } = await buy(call, "alpenland-bus.tagesticket-salzkammergut");
  const own = (await call("POST", "/v1/coverage", { tickets: [ticket.token], journeys: await journeys("salzburg", "fuschl") })).body;
  assert.deepEqual([own.entitlements[0].verified, own.journeys[0].coverage.status, own.journeys[0].coverage.approximate, own.journeys[1].coverage.status], [true, "full", false, "none"]);
  const scanned = (await call("POST", "/v1/recognize", { barcodes: [ticket.token, "#UT01..."] })).body;
  assert.deepEqual(scanned.barcodes, [{ format: "publit" }, { format: "uic-918-3" }]);
  assert.equal(scanned.tickets[0].verified, true);
  assert.equal((await call("POST", "/v1/coverage", { tickets: ["PT1.bad.bad"], journeys: [] })).body.problems[0].code, "not_valid");

  // The demo console can act as Publit and as the demo operator; outside demo mode none of this exists.
  const demo = (await call("GET", "/v1/demo")).body;
  assert.equal(demo.adminToken, "admin-secret");
  assert.equal((await call("GET", "/v1/operator", undefined, demo.operatorKeys["alpenland-bus"])).body.operator.name, "Alpenland Bus");
  assert.equal((await call("POST", "/v1/demo/reset", {})).status, 200);
  assert.equal((await call("GET", `/v1/orders/x`)).status, 404);
  assert.equal(clock.now, Date.parse("2026-11-28T13:00:00Z"));
});

test("outside demo mode there is no demo console and no free payment", async () => {
  const store = createStore();
  const app = createApp({ store, env: { ADMIN_TOKEN: "a" } });
  const get = async (path, method = "GET", body) => (await app(new Request(`http://core${path}`, { method, body: body && JSON.stringify(body) }))).status;
  assert.equal(await get("/v1/demo"), 404);
  assert.equal(await get("/v1/demo/reset", "POST", {}), 404);
  assert.equal(Object.keys(store.data.operators).length, 0);
  assert.equal(await get("/health"), 200);
  assert.equal((await app(new Request("http://core/v1/products", { method: "OPTIONS" }))).status, 204);
});

// ---- check formats: the code each operator's own devices read ---------------------------------------------------

async function withDayTicket(call) {
  const operator = await onboard(call);
  const created = await call("POST", "/v1/operator/products", { name: "Tageskarte", template: "day", price: { amount: 900, currency: "EUR" } }, operator.key);
  assert.equal(created.status, 201);
  return { ...operator, productId: created.body.product.id };
}

test("format: only Publit sets it, and the secret never comes back out", async () => {
  const { call, store } = setup();
  const operator = await withDayTicket(call);
  const format = { type: "shared-secret", config: { template: "{id}|{from}|{until}", length: 16 }, secret: "the-operators-own-secret-123" };
  assert.equal((await call("POST", `/v1/admin/operators/${operator.id}/format`, format)).status, 401);
  assert.equal((await call("POST", `/v1/admin/operators/${operator.id}/format`, format, operator.key)).status, 401);
  assert.equal((await call("GET", "/v1/admin/operators", undefined, operator.key)).status, 401);
  assert.equal((await call("POST", "/v1/admin/verify", { code: "x" })).status, 401);
  const set = await call("POST", `/v1/admin/operators/${operator.id}/format`, format, "admin-secret");
  assert.equal(set.status, 200, JSON.stringify(set.body));
  assert.deepEqual({ type: set.body.operator.format.type, hasSecret: set.body.operator.format.hasSecret }, { type: "shared-secret", hasSecret: true });
  const everything = JSON.stringify([set.body, (await call("GET", "/v1/admin/operators", undefined, "admin-secret")).body, (await call("GET", "/v1/operators")).body, (await call("GET", "/v1/operator", undefined, operator.key)).body]);
  assert.ok(!everything.includes("the-operators-own-secret-123"));
  assert.ok(!JSON.stringify(store.data).includes("the-operators-own-secret-123"), "the store holds the secret only encrypted");
  // Changing the layout without sending the secret again keeps the secret.
  const again = await call("POST", `/v1/admin/operators/${operator.id}/format`, { type: "shared-secret", config: { template: "{id}|{until}" } }, "admin-secret");
  assert.equal(again.body.operator.format.hasSecret, true);
  for (const bad of [{ type: "nope" }, { type: "shared-secret", config: { template: "no id" }, secret: "the-operators-own-secret-123" }, { type: "operator-api", config: { endpoint: "http://insecure.example/x" }, secret: "tok" },
    { type: "uic-918-3", config: { rics: "12" } }, { type: "uic-918-3", config: { rics: "1234" }, secret: "not a key" }]) {
    assert.equal((await call("POST", `/v1/admin/operators/${operator.id}/format`, bad, "admin-secret")).status, 400, JSON.stringify(bad));
  }
});

test("format shared-secret: the ticket carries the checksum the operator's devices compute", async () => {
  const { call, clock } = setup();
  const operator = await withDayTicket(call);
  const secret = "the-operators-own-secret-123";
  await call("POST", `/v1/admin/operators/${operator.id}/format`, { type: "shared-secret", config: { template: "{id}|{from}|{until}|{n}", length: 16 }, secret }, "admin-secret");
  const { ticket } = await buy(call, operator.productId);
  assert.equal(ticket.format, "shared-secret");
  // What the operator's device does, written independently of the server code.
  const cut = ticket.code.lastIndexOf("|");
  assert.equal(ticket.code.slice(cut + 1), createHmac("sha256", secret).update(ticket.code.slice(0, cut)).digest("hex").slice(0, 16));
  assert.ok(ticket.code.startsWith(`${ticket.id}|`));
  assert.match(ticket.token, /^PT1\./, "Publit's own signed record exists as well");

  const good = await call("POST", "/v1/admin/verify", { code: ticket.code }, "admin-secret");
  assert.equal(good.body.guaranteed, true, JSON.stringify(good.body));
  assert.equal(good.body.ticket.id, ticket.id);
  assert.equal((await call("POST", "/v1/admin/verify", { code: ticket.token }, "admin-secret")).body.guaranteed, true);
  const forged = await call("POST", "/v1/admin/verify", { code: ticket.code.replace(/.$/, (c) => (c === "0" ? "1" : "0")) }, "admin-secret");
  assert.deepEqual([forged.body.guaranteed, forged.body.code], [false, "not_issued"]);
  assert.equal((await call("POST", "/v1/validate", { code: ticket.code })).body.level, "valid");

  await call("POST", `/v1/operator/tickets/${ticket.id}/revoke`, { reason: "refund" }, operator.key);
  assert.equal((await call("POST", "/v1/admin/verify", { code: ticket.code }, "admin-secret")).body.code, "revoked");
  const second = (await buy(call, operator.productId)).ticket;
  clock.now += 3 * 86400000;
  assert.equal((await call("POST", "/v1/admin/verify", { code: second.code }, "admin-secret")).body.code, "expired");
});

test("format uic-918-3: a signed rail barcode; the public key is what the operator gets", async () => {
  const { call } = setup();
  const operator = await withDayTicket(call);
  const set = await call("POST", `/v1/admin/operators/${operator.id}/format`, { type: "uic-918-3", config: { rics: "9999", keyId: "7" } }, "admin-secret");
  assert.equal(set.status, 200, JSON.stringify(set.body));
  const publicKey = set.body.operator.format.config.publicKeyPem;
  assert.match(publicKey, /BEGIN PUBLIC KEY/);
  assert.ok(!JSON.stringify(set.body).includes("PRIVATE KEY"));
  const { ticket } = await buy(call, operator.productId);
  assert.deepEqual([ticket.format, ticket.symbology, ticket.codeEncoding], ["uic-918-3", "aztec", "base64"]);
  const bytes = Buffer.from(ticket.code, "base64");
  assert.equal(bytes.subarray(0, 14).toString("latin1"), "#UT01999900007");
  const read = decodeUic918(bytes, publicKey);
  assert.equal(read.signed, true);
  assert.equal(read.ticketId, ticket.id);
  assert.ok(read.fields.some((f) => f.text === "Tageskarte"));
  // One changed byte in the signed part: the signature no longer fits.
  const changed = Buffer.from(bytes);
  changed[20] ^= 1;
  assert.notEqual(decodeUic918(changed, publicKey)?.signed, true);
  assert.equal((await call("POST", "/v1/admin/verify", { code: ticket.code }, "admin-secret")).body.guaranteed, true);
  const sample = await call("POST", `/v1/admin/operators/${operator.id}/format/test`, {}, "admin-secret");
  assert.deepEqual([sample.body.test, sample.body.check, sample.body.symbology], [true, true, "aztec"]);
  assert.equal((await call("POST", "/v1/admin/verify", { code: sample.body.code }, "admin-secret")).body.guaranteed, false, "a test code is not a ticket");
});

test("format operator-api: the operator's system issues the code; if it does not answer nothing is sold", async () => {
  const seen = [];
  let up = true;
  const fetch = async (url, init) => {
    seen.push({ url, auth: init.headers.authorization, body: JSON.parse(init.body) });
    return up ? Response.json({ code: `OPERATOR-${seen.length}-ORIGINAL`, reference: "B-4711" }) : new Response("down", { status: 503 });
  };
  const { call, store } = setup({ fetch });
  const added = await call("POST", "/v1/admin/operators", { name: "Seebahn AG", country: "AT", contactEmail: "it@seebahn.example", level: "api",
    format: { type: "operator-api", config: { endpoint: "https://sales.seebahn.example/tickets", symbology: "aztec" }, secret: "their-api-token-xyz" } }, "admin-secret");
  assert.equal(added.status, 201, JSON.stringify(added.body));
  assert.equal(added.body.operator.status, "active");
  const created = await call("POST", "/v1/operator/products", { name: "Tageskarte", template: "day", price: { amount: 900, currency: "EUR" } }, added.body.apiKey);
  const { ticket } = await buy(call, created.body.product.id);
  assert.equal(ticket.code, "OPERATOR-1-ORIGINAL");
  assert.deepEqual([seen[0].url, seen[0].auth, seen[0].body.reference], ["https://sales.seebahn.example/tickets", "Bearer their-api-token-xyz", ticket.id]);
  const verified = await call("POST", "/v1/admin/verify", { code: "OPERATOR-1-ORIGINAL" }, "admin-secret");
  assert.deepEqual([verified.body.guaranteed, verified.body.ticket.reference], [true, "B-4711"]);
  assert.equal(verified.body.checks.find((c) => c.name === "format").code, "format_operator");

  up = false;
  const order = await call("POST", "/v1/orders", { productId: created.body.product.id });
  const paid = await call("POST", `/v1/orders/${order.body.order.id}/pay`, { secret: order.body.order.secret });
  assert.deepEqual([paid.status, paid.body.error], [502, "operator_system"]);
  assert.equal(store.data.orders[order.body.order.id].status, "pending_payment");
  assert.equal(Object.keys(store.data.tickets).length, 1);
});

test("vault: without the right SECRETS_KEY a stored secret opens nothing", async () => {
  const none = setup({ secretsKey: "" });
  const operator = await withDayTicket(none.call);
  const refused = await none.call("POST", `/v1/admin/operators/${operator.id}/format`, { type: "shared-secret", secret: "the-operators-own-secret-123" }, "admin-secret");
  assert.deepEqual([refused.status, refused.body.error], [503, "no_secrets_key"]);

  const first = setup();
  const op = await withDayTicket(first.call);
  await first.call("POST", `/v1/admin/operators/${op.id}/format`, { type: "shared-secret", secret: "the-operators-own-secret-123" }, "admin-secret");
  // The same data file under another key, as after a stolen copy.
  const other = createApp({ store: first.store, env: { ADMIN_TOKEN: "admin-secret", DEMO_PAYMENTS: "on", SECRETS_KEY: "another-key-entirely-0123456789" }, now: () => first.clock.now });
  const order = await first.call("POST", "/v1/orders", { productId: op.productId });
  const response = await other(new Request(`http://core/v1/orders/${order.body.order.id}/pay`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ secret: order.body.order.secret }) }));
  assert.deepEqual([response.status, (await response.json()).error], [409, "secret_unreadable"]);
});

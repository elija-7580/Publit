// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import { test } from "node:test";
import assert from "node:assert/strict";
import { findJourneys, journeyFrom, parseJourneyRequest, routerURL, total } from "../src/journeys.js";
import { ShopError } from "../src/shop.js";
import worker from "../src/index.js";

const SECRET = "test-secret-with-enough-characters-1234";
const ROUTER = "https://route.example.org";

const itinerary = {
  startTime: "2026-12-01T08:00:00Z", endTime: "2026-12-01T10:30:00Z", duration: 9000, transfers: 1,
  legs: [
    { mode: "WALK", from: { name: "Home", lat: 48.2, lon: 16.37 }, to: { name: "Wien Hbf", lat: 48.185, lon: 16.376 },
      startTime: "2026-12-01T08:00:00Z", endTime: "2026-12-01T08:10:00Z" },
    { mode: "HIGHSPEED_RAIL", displayName: "RJX 161", agencyName: "ÖBB", headsign: "Salzburg",
      from: { name: "Wien Hbf", lat: 48.185, lon: 16.376, stopId: "at-oebb_1" }, to: { name: "Linz Hbf", lat: 48.29, lon: 14.29 },
      startTime: "2026-12-01T08:15:00Z", endTime: "2026-12-01T09:30:00Z" },
    { mode: "BUS", routeShortName: "FLX 042", agencyName: "FlixBus",
      from: { name: "Linz Hbf", lat: 48.29, lon: 14.29 }, to: { name: "Passau", lat: 48.57, lon: 13.43 },
      startTime: "2026-12-01T09:40:00Z", endTime: "2026-12-01T10:30:00Z", agencyUrl: "https://www.flixbus.de" },
  ],
};

function router(captured = {}) {
  return async (url) => {
    captured.url = new URL(url);
    return new Response(JSON.stringify({ itineraries: [itinerary] }), { headers: { "Content-Type": "application/json" } });
  };
}

test("only an own router is asked, never Transitous", () => {
  assert.throws(() => routerURL({}), (e) => e instanceof ShopError && e.status === 503);
  assert.throws(() => routerURL({ ROUTER_URL: "https://api.transitous.org" }), (e) => e.status === 503);
  assert.throws(() => routerURL({ ROUTER_URL: "https://europe.motis-project.de" }), (e) => e.status === 503);
  assert.throws(() => routerURL({ ROUTER_URL: "http://route.example.org" }), (e) => e.status === 503);
  assert.equal(routerURL({ ROUTER_URL: ROUTER }).hostname, "route.example.org");
  assert.equal(routerURL({ ROUTER_URL: "http://127.0.0.1:8080" }).port, "8080");
});

test("requests need two places and sane limits", () => {
  assert.throws(() => parseJourneyRequest({ from: { lat: 48.2, lon: 16.3 } }), ShopError);
  assert.throws(() => parseJourneyRequest({ from: { lat: 48.2, lon: 16.3 }, to: { lat: 47, lon: 13 }, results: 9 }), ShopError);
  assert.throws(() => parseJourneyRequest({ from: { lat: 48.2, lon: 16.3 }, to: { lat: 47, lon: 13 }, time: "soon" }), ShopError);
  const r = parseJourneyRequest({ from: { stopId: "at-oebb_1" }, to: { lat: 47.8, lon: 13.04 } });
  assert.equal(r.from, "at-oebb_1");
  assert.equal(r.to, "47.8,13.04");
  assert.equal(r.results, 3);
});

test("a MOTIS itinerary becomes legs with transit flags and the feed's links", () => {
  const j = journeyFrom(itinerary);
  assert.equal(j.legs.length, 3);
  assert.deepEqual(j.legs.map((l) => l.transit), [false, true, true]);
  assert.equal(j.legs[1].line, "RJX 161");
  assert.equal(j.legs[2].line, "FLX 042");
  assert.equal(j.legs[2].links.website, "https://www.flixbus.de");
  assert.equal(j.transfers, 1);
});

test("the total exists only when every ride has an offer in one currency", () => {
  const j = journeyFrom(itinerary);
  assert.equal(total(j, [{ amount: 100, currency: "EUR" }]), null);
  assert.deepEqual(total(j, [{ amount: 100, currency: "EUR" }, { amount: 50, currency: "EUR" }]), { amount: 150, currency: "EUR" });
  assert.equal(total(j, [{ amount: 100, currency: "EUR" }, { amount: 50, currency: "CZK" }]), null);
});

test("journeys come with an offer per ride when the shop can sell it", async () => {
  const captured = {};
  const env = { ROUTER_URL: ROUTER, TOKEN_SECRET: SECRET, DEMO_PROVIDER: "on" };
  const result = await findJourneys({ from: { lat: 48.2, lon: 16.37 }, to: { lat: 48.57, lon: 13.43 },
    time: "2026-12-01T08:00:00Z", results: 2 }, env, { fetchImpl: router(captured) });
  assert.equal(captured.url.origin, ROUTER);
  assert.equal(captured.url.pathname, "/api/v6/plan");
  assert.equal(captured.url.searchParams.get("fromPlace"), "48.2,16.37");
  assert.equal(captured.url.searchParams.get("numItineraries"), "2");
  const [journey] = result.journeys;
  assert.deepEqual(journey.offers.map((o) => o.leg), [1, 2]);
  assert.ok(journey.offers.every((o) => typeof o.token === "string"));
  assert.deepEqual(journey.links, []);
  assert.equal(journey.total.currency, "EUR");
});

test("rides the shop cannot sell get a link instead", async () => {
  const env = { ROUTER_URL: ROUTER, TOKEN_SECRET: SECRET, DEMO_PROVIDER: "off", PARTNER_TEMPLATES: "{}" };
  const result = await findJourneys({ from: { lat: 48.2, lon: 16.37 }, to: { lat: 48.57, lon: 13.43 } }, env,
    { fetchImpl: router() });
  const [journey] = result.journeys;
  assert.deepEqual(journey.offers, []);
  assert.equal(journey.total, null);
  const byLeg = Object.fromEntries(journey.links.map((l) => [l.leg, l]));
  assert.equal(byLeg[2].url, "https://www.flixbus.de/"); // the feed's own website
  assert.match(byLeg[1].url, /oebb/); // known shop of the operator
});

test("the worker answers /v1/journeys with CORS, and 503 without an own router", async () => {
  const request = (env) => worker.fetch(new Request("https://shop.example.org/v1/journeys", {
    method: "POST", body: JSON.stringify({ from: { lat: 48.2, lon: 16.37 }, to: { lat: 48.57, lon: 13.43 } }),
  }), env, {}, { fetch: router() });
  const off = await request({ TOKEN_SECRET: SECRET });
  assert.equal(off.status, 503);
  assert.equal(off.headers.get("Access-Control-Allow-Origin"), "*");
  const on = await request({ TOKEN_SECRET: SECRET, ROUTER_URL: ROUTER, DEMO_PROVIDER: "on" });
  assert.equal(on.status, 200);
  assert.equal((await on.json()).journeys.length, 1);
});

// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import { test } from "node:test";
import assert from "node:assert/strict";
import { findLinks, knownShop, partners, validTemplate, withSubId, PROGRAMS } from "../src/links.js";
import { ShopError } from "../src/shop.js";
import worker from "../src/index.js";

const flix = PROGRAMS.find((p) => p.id === "flixbus");
const AWIN = "https://www.awin1.com/cread.php?awinmid=1&awinaffid=2&ued={url}";
const env = { PARTNER_TEMPLATES: JSON.stringify({ flixbus: AWIN, omio: "https://evil.example/?u={url}" }) };

test("templates must be https on the network's host with one {url}", () => {
  assert.ok(validTemplate(flix, AWIN));
  assert.ok(!validTemplate(flix, "http://www.awin1.com/?ued={url}"));
  assert.ok(!validTemplate(flix, "https://awin1.com.evil.example/?ued={url}"));
  assert.ok(!validTemplate(flix, "https://www.awin1.com/?ued=x"));
  assert.ok(!validTemplate(flix, "https://www.awin1.com/?a={url}&b={url}"));
});

test("only valid Publit templates are published", () => {
  assert.deepEqual(partners(env).programs.map((p) => p.id), ["flixbus"]);
  assert.deepEqual(partners({ PARTNER_TEMPLATES: "not json" }).programs, []);
});

test("known shops match operator words, longest first", () => {
  assert.equal(knownShop("ÖBB Personenverkehr"), "https://tickets.oebb.at");
  assert.equal(knownShop("Wiener Linien GmbH"), "https://shop.wienerlinien.at");
  assert.equal(knownShop("Unknown Bus"), null);
});

test("links prefer feed links, wrap partner shops and let callers bring their own ID", () => {
  const body = {
    legs: [
      { index: 0, operator: "FlixBus", links: { booking: "https://shop.flixbus.de/search?x=1" } },
      { index: 1, operator: "ÖBB" },
      { index: 2, operator: "Nobody" },
      { index: 3, operator: "FlixBus", links: { booking: "javascript:alert(1)", website: "https://www.flixbus.at" } },
    ],
  };
  const { links } = findLinks(body, env);
  assert.deepEqual(links.map((l) => l.leg), [0, 1, 3]);
  assert.equal(links[0].via, "publit");
  assert.equal(new URL(links[0].url).searchParams.get("ued"), "https://shop.flixbus.de/search?x=1");
  assert.deepEqual([links[1].url, links[1].partner], ["https://tickets.oebb.at/", null]);
  assert.equal(links[2].source, "website");

  const own = "https://www.awin1.com/cread.php?awinmid=1&awinaffid=999&ued={url}";
  const mine = findLinks({ ...body, partners: { flixbus: own } }, env).links[0];
  assert.equal(mine.via, "caller");
  assert.equal(new URL(mine.url).searchParams.get("awinaffid"), "999");
  assert.throws(() => findLinks({ ...body, partners: { flixbus: "https://evil.example/{url}" } }, env), ShopError);
  assert.throws(() => findLinks({ legs: [] }, env), ShopError);
});

test("the link layer works without shop secrets and allows browsers", async () => {
  const post = new Request("https://shop.example/v1/links", { method: "POST", body: JSON.stringify({ legs: [{ operator: "SBB" }] }) });
  const res = await worker.fetch(post, {});
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("Access-Control-Allow-Origin"), "*");
  assert.equal((await res.json()).links[0].url, "https://www.sbb.ch/");
  const get = await worker.fetch(new Request("https://shop.example/v1/partners"), env);
  assert.equal((await get.json()).programs.length, 1);
  const bad = await worker.fetch(new Request("https://shop.example/v1/links", { method: "POST", body: "{}" }), {});
  assert.equal(bad.status, 400);
});

test("apps sharing Publit's links are told apart by the network's sub-ID", () => {
  const body = { legs: [{ index: 0, operator: "FlixBus", links: { booking: "https://shop.flixbus.de/x" } }], app: "city-app" };
  const link = new URL(findLinks(body, env).links[0].url);
  assert.equal(link.searchParams.get("clickref"), "city-app");
  assert.equal(link.searchParams.get("ued"), "https://shop.flixbus.de/x");
  assert.equal(withSubId("partnerize", "https://prf.hn/click/camref:1/destination:x", "a"), "https://prf.hn/click/camref:1/pubref:a/destination:x");
  assert.equal(new URL(withSubId("impact", "https://omio.sjv.io/c/1/2/3?u=x", "a")).searchParams.get("subId1"), "a");
  const own = findLinks({ ...body, partners: { flixbus: AWIN.replace("awinaffid=2", "awinaffid=9") } }, env).links[0].url;
  assert.equal(new URL(own).searchParams.get("clickref"), null);
  assert.throws(() => findLinks({ ...body, app: "Bad App!" }, env), ShopError);
});

test("DB legs get a bahn.de search with start, destination and local departure time", () => {
  const { links } = findLinks({ legs: [
    { index: 0, operator: "DB Fernverkehr AG", from: "München Hbf", to: "Nürnberg Hbf", departure: "2026-11-25T07:00:00Z",
      links: { website: "https://www.bahn.de" } },
    { index: 1, operator: "DB Regio", from: "A", to: "B" },
  ] }, {});
  assert.equal(links[0].source, "search");
  assert.ok(links[0].url.startsWith("https://www.bahn.de/buchung/fahrplan/suche#sts=true&"), links[0].url);
  assert.ok(links[0].url.includes("so=M%C3%BCnchen%20Hbf"), links[0].url);
  assert.ok(links[0].url.includes("soid=A%3D1%40O%3DM%C3%BCnchen%20Hbf%40"), links[0].url);
  assert.ok(links[0].url.includes("hd=2026-11-25T08:00:00"), links[0].url);
  // Without a departure time the leg falls back to the known shop.
  assert.equal(links[1].source, "fares");
});

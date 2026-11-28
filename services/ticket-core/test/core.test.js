// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import test from "node:test";
import assert from "node:assert/strict";
import { generateKeyPair, signTicket, parseTicket, verifyTicketSignature, present, verifyProof, deviceKeyFromJwk, isPublicJwk } from "../src/core/token.js";
import { b64u, unb64u, canonical, fingerprint, plain, encoder } from "../src/core/bytes.js";
import { resolveWindow, zoned } from "../src/core/time.js";
import { coverLeg, coverJourney, legOperator, routerModes } from "../src/core/coverage.js";
import { pointInRing, stopCountry } from "../src/core/geo.js";
import { describeValidity } from "../src/core/describe.js";

const OPERATORS = [
  { id: "oebb", name: "ÖBB", aliases: ["Österreichische Bundesbahnen"] },
  { id: "postbus", name: "Postbus", aliases: ["ÖBB-Postbus"] },
  { id: "flixbus", name: "FlixBus", aliases: [] },
  { id: "cat", name: "City Airport Train", aliases: ["CAT"] },
];
const wien = { stopId: "s:wien", name: "Wien Hbf", lat: 48.185, lon: 16.376, country: "AT" };
const linz = { stopId: "s:linz", name: "Linz Hbf", lat: 48.29, lon: 14.29, country: "AT" };
const muenchen = { stopId: "s:muc", name: "München Hbf", lat: 48.14, lon: 11.558, country: "DE" };
const T0 = Date.parse("2026-12-01T08:00:00Z");
const ride = (mode, from, to, agencyName, offsetMinutes = 0, minutes = 60, line = "1") => ({
  mode, from, to, agencyName, routeShortName: line,
  startTime: new Date(T0 + offsetMinutes * 60000).toISOString(), endTime: new Date(T0 + (offsetMinutes + minutes) * 60000).toISOString(),
});
const pass = (validity, hours = 24) => ({ validFrom: T0, validUntil: T0 + hours * 3600000, validity: { time: { type: "duration", minutes: hours * 60 }, operators: "any", area: [], ...validity } });

test("bytes: base64url round trip, canonical JSON and plain names", async () => {
  const bytes = Uint8Array.from([0, 250, 251, 252, 253, 254, 255]);
  assert.deepEqual(unb64u(b64u(bytes)), bytes);
  assert.equal(canonical({ b: 1, a: [2, { d: 1, c: 2 }] }), '{"a":[2,{"c":2,"d":1}],"b":1}');
  assert.equal(await fingerprint({ a: 1, b: 2 }), await fingerprint({ b: 2, a: 1 }));
  assert.equal(plain("ÖBB-Postbus Straße"), "obb postbus strasse");
});

test("token: a signed ticket verifies, a changed one does not", async () => {
  const key = await generateKeyPair();
  const other = await generateKeyPair();
  const token = await signTicket({ id: "T1", iss: "op", nbf: 1, exp: 2 }, key.privateJwk);
  const parsed = parseTicket(token);
  assert.equal(parsed.payload.id, "T1");
  assert.equal(await verifyTicketSignature(parsed, key.publicJwk), true);
  assert.equal(await verifyTicketSignature(parsed, other.publicJwk), false);
  const [prefix, , signature] = token.split(".");
  const forged = `${prefix}.${b64u(encoder.encode(JSON.stringify({ id: "T1", iss: "op", nbf: 1, exp: 99999999999 })))}.${signature}`;
  assert.equal(await verifyTicketSignature(parseTicket(forged), key.publicJwk), false);
  assert.equal(parseTicket("hello"), null);
  assert.equal(parseTicket("PT1.x.y"), null);
  assert.equal(isPublicJwk(key.publicJwk), true);
  assert.equal(isPublicJwk(key.privateJwk), false);
});

test("token: the live proof belongs to one device and one moment", async () => {
  const issuer = await generateKeyPair();
  const device = await generateKeyPair();
  const thief = await generateKeyPair();
  const token = await signTicket({ id: "T2", iss: "op", dk: deviceKeyFromJwk(device.publicJwk) }, issuer.privateJwk);
  const shown = parseTicket(await present(token, device.privateJwk, 1800000000));
  assert.equal(shown.proof.at, 1800000000);
  assert.equal(await verifyProof(shown), true);
  assert.equal(await verifyTicketSignature(shown, issuer.publicJwk), true);
  assert.equal(await verifyProof(parseTicket(await present(token, thief.privateJwk, 1800000000))), false);
  assert.equal(await verifyProof(parseTicket(token)), false);
});

test("time: duration, calendar day with late end, month and year, across the clock change", () => {
  const zone = "Europe/Vienna";
  assert.equal(zoned(2026, 12, 1, 9, zone), Date.parse("2026-12-01T08:00:00Z"));
  assert.equal(zoned(2026, 7, 1, 9, zone), Date.parse("2026-07-01T07:00:00Z"));
  assert.deepEqual(resolveWindow({ type: "duration", minutes: 1440 }, T0, zone), { from: T0, until: T0 + 86400000 });
  assert.equal(resolveWindow({ type: "calendar", unit: "day", count: 1 }, T0, zone).until, Date.parse("2026-12-01T22:59:59Z"));
  assert.equal(resolveWindow({ type: "calendar", unit: "day", count: 1, endHour: 1 }, T0, zone).until, Date.parse("2026-12-01T23:59:59Z"));
  assert.equal(resolveWindow({ type: "calendar", unit: "month", count: 1 }, T0, zone).until, Date.parse("2026-12-31T22:59:59Z"));
  assert.equal(resolveWindow({ type: "calendar", unit: "year", count: 1 }, T0, zone).until, Date.parse("2027-11-30T22:59:59Z"));
  // 24 October 2026, 12:00 in Vienna is summer time; the day ticket still ends at local midnight after the change.
  const beforeChange = Date.parse("2026-10-24T10:00:00Z");
  assert.equal(resolveWindow({ type: "calendar", unit: "day", count: 2 }, beforeChange, zone).until, Date.parse("2026-10-25T22:59:59Z"));
});

test("geo: outline test and a stop's country from field, id or position", () => {
  const square = [[0, 0], [2, 0], [2, 2], [0, 2]];
  assert.equal(pointInRing(1, 1, square), true);
  assert.equal(pointInRing(3, 1, square), false);
  assert.deepEqual(stopCountry({ country: "at" }), { code: "AT", approximate: false });
  assert.deepEqual(stopCountry({ stopId: "de-DELFI_de:09162:6" }), { code: "DE", approximate: false });
  assert.deepEqual(stopCountry({ lat: 48.29, lon: 14.29 }), { code: "AT", approximate: true });
  assert.deepEqual(stopCountry({ lat: 48.14, lon: 11.558 }), { code: "DE", approximate: true });
  assert.equal(stopCountry({ name: "Nowhere" }), null);
});

test("coverage: operator is found by its longest alias", () => {
  assert.equal(legOperator({ agencyName: "ÖBB-Postbus GmbH" }, OPERATORS), "postbus");
  assert.equal(legOperator({ agencyName: "Österreichische Bundesbahnen" }, OPERATORS), "oebb");
  assert.equal(legOperator({ agencyName: "Someone Else" }, OPERATORS), null);
  assert.equal(legOperator({ operatorId: "cat", agencyName: "whatever" }, OPERATORS), "cat");
});

test("coverage: time window, modes, operators, exceptions", () => {
  const context = { operators: OPERATORS };
  const ticket = pass({ operators: ["oebb", "postbus"], modes: { except: ["COACH"] }, except: [{ operators: ["oebb"], lines: ["NJ 40"], label: { de: "Nachtzug", en: "night train" } }] });
  assert.equal(coverLeg(ride("REGIONAL_RAIL", wien, linz, "ÖBB"), ticket, context).covered, true);
  assert.equal(coverLeg(ride("WALK", wien, linz), ticket, context).reason, "no_ticket_needed");
  assert.equal(coverLeg(ride("REGIONAL_RAIL", wien, linz, "ÖBB", -30), ticket, context).reason, "before_start");
  assert.equal(coverLeg(ride("REGIONAL_RAIL", wien, linz, "ÖBB", 25 * 60), ticket, context).reason, "after_end");
  assert.equal(coverLeg(ride("COACH", wien, linz, "Postbus"), ticket, context).reason, "mode");
  assert.equal(coverLeg(ride("BUS", wien, linz, "FlixBus"), ticket, context).reason, "operator");
  assert.equal(coverLeg(ride("BUS", wien, linz, "Unknown Lines"), ticket, context).covered, null);
  const night = coverLeg(ride("NIGHT_RAIL", wien, linz, "ÖBB", 0, 60, "NJ 40"), ticket, context);
  assert.equal(night.reason, "excepted");
  assert.equal(night.detail.de, "Nachtzug");
  // A ride that starts in time may be finished, unless the product says otherwise.
  assert.equal(coverLeg(ride("REGIONAL_RAIL", wien, linz, "ÖBB", 23 * 60 + 30), ticket, context).covered, true);
  assert.equal(coverLeg(ride("REGIONAL_RAIL", wien, linz, "ÖBB", 23 * 60 + 30), pass({ rideOut: false }), context).reason, "ends_after_end");
});

test("coverage: country, zone by stop list and by outline, border stations", () => {
  const context = { operators: OPERATORS };
  const austria = pass({ area: [{ type: "country", code: "AT" }] });
  assert.equal(coverLeg(ride("REGIONAL_RAIL", wien, linz, "ÖBB"), austria, context).covered, true);
  const abroad = coverLeg(ride("HIGHSPEED_RAIL", wien, muenchen, "ÖBB"), austria, context);
  assert.deepEqual([abroad.covered, abroad.reason, abroad.detail], [false, "area", "München Hbf"]);
  // A stop in between that lies outside breaks the cover.
  const through = { ...ride("HIGHSPEED_RAIL", wien, linz, "ÖBB"), intermediateStops: [muenchen] };
  assert.equal(coverLeg(through, austria, context).covered, false);
  assert.equal(coverLeg(ride("BUS", { name: "Somewhere" }, linz, "ÖBB"), austria, context).reason, "area_unknown");

  const zone = pass({ area: [{ type: "zone", id: "z", name: "Z", stops: ["s:wien"], ring: [[14, 48], [15, 48], [15, 49], [14, 49]] }] });
  assert.equal(coverLeg(ride("BUS", wien, linz, "ÖBB"), zone, context).covered, true);
  assert.equal(coverLeg(ride("BUS", wien, muenchen, "ÖBB"), zone, context).covered, false);
  const rough = pass({ area: [{ type: "zone", id: "z", name: "Z", ring: [[14, 48], [15, 48], [15, 49], [14, 49]], approximate: true }] });
  assert.equal(coverLeg(ride("BUS", linz, linz, "ÖBB"), rough, context).certainty, "approximate");

  const germanyPlus = pass({ area: [{ type: "country", code: "DE" }, { type: "stops", stops: [{ id: "s:linz", name: "Linz Hbf" }] }] });
  assert.equal(coverLeg(ride("REGIONAL_RAIL", linz, muenchen, "ÖBB"), germanyPlus, context).covered, true);
  assert.equal(coverLeg(ride("REGIONAL_RAIL", wien, muenchen, "ÖBB"), germanyPlus, context).covered, false);
});

test("coverage: a ticket between two stops covers the rides between them, and a journey is summed up", () => {
  const context = { operators: OPERATORS };
  const single = { ...pass({ operators: ["oebb"], area: [{ type: "route" }] }), od: { from: { id: "s:wien" }, to: { name: "München Hbf" } } };
  const journey = { legs: [ride("WALK", { name: "Home" }, wien), ride("REGIONAL_RAIL", wien, linz, "ÖBB", 10), ride("REGIONAL_RAIL", linz, muenchen, "ÖBB", 80), ride("BUS", muenchen, { name: "Hotel", lat: 48.2, lon: 11.6 }, "FlixBus", 150)] };
  const result = coverJourney(journey, [single], context);
  assert.deepEqual(result.legs.map((l) => l.covered), [true, true, true, false]);
  assert.equal(result.status, "partial");
  assert.equal(result.legs[3].reason, "operator");
  assert.equal(coverJourney({ legs: journey.legs.slice(0, 3) }, [single], context).status, "full");
  assert.equal(coverJourney(journey, [], context).status, "none");
  // Two tickets together: the second one covers what the first does not.
  const cityBus = pass({ operators: ["flixbus"] });
  const both = coverJourney(journey, [single, cityBus], context);
  assert.equal(both.status, "full");
  assert.equal(both.legs[3].by, 1);
  // The other direction is not the ticket's route.
  const back = { legs: [ride("REGIONAL_RAIL", muenchen, wien, "ÖBB")] };
  assert.equal(coverJourney(back, [single], context).legs[0].reason, "route");
});

test("coverage: router modes leave out what the ticket never covers", () => {
  const modes = routerModes({ modes: { except: ["HIGHSPEED_RAIL", "COACH"] } });
  assert.equal(modes.includes("HIGHSPEED_RAIL"), false);
  assert.equal(modes.includes("REGIONAL_RAIL"), true);
  assert.deepEqual(routerModes({ modes: { only: ["BUS"] } }), ["BUS"]);
});

test("describe: the scope reads the same from data in German and English", () => {
  const validity = { timeZone: "Europe/Vienna", time: { type: "duration", minutes: 1440 }, operators: ["oebb"],
    area: [{ type: "country", code: "AT" }, { type: "zone", id: "100", name: { de: "Wien", en: "Vienna" }, stops: ["x"] }],
    modes: { except: ["COACH"] }, except: [{ operators: ["cat"], label: { de: "CAT", en: "CAT" } }], rides: "unlimited", class: 2, personal: true };
  const de = describeValidity(validity, { language: "de", window: { from: T0, until: T0 + 86400000 }, operators: OPERATORS });
  assert.equal(de.when, "Gilt ab 01.12.2026, 09:00 bis 02.12.2026, 09:00 (Europe/Vienna)");
  assert.deepEqual(de.where, ["ganz Österreich", "Zone Wien"]);
  assert.equal(de.operators, "ÖBB");
  assert.deepEqual(de.notValid, ["nicht in Fernbus", "CAT"]);
  assert.equal(de.conditions.includes("Persönlich, nur mit Ausweis"), true);
  const en = describeValidity(validity, { language: "en", operators: OPERATORS });
  assert.equal(en.when, null);
  assert.equal(en.duration, "24 hours from the start of validity");
  assert.deepEqual(en.where, ["all of Austria", "zone Vienna"]);
});

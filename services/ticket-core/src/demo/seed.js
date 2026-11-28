// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Demo data. Loaded only with DEMO=on.
//
// - "Alpenland Bus" is an invented operator that sells through this platform.
// - The real companies are only directory entries (name and aliases), as they appear in timetable data.
//   None of them has a contract with Publit and nothing of theirs is sold here.
// - KlimaTicket Ö, Deutschlandticket and the Vienna hour tickets are modelled from public information so the
//   photo flow has something to recognise. They are marked `approximate` until the issuer confirms the rules.
// - Connections are fixed samples, not a timetable.

import { listOperator, applyOperator, approveOperator } from "../operators.js";
import { saveProduct } from "../products.js";

export const STOPS = {
  stephansplatz: { stopId: "demo:wien-stephansplatz", name: "Wien Stephansplatz", lat: 48.2085, lon: 16.3725, country: "AT" },
  wienHbf: { stopId: "demo:wien-hbf", name: "Wien Hauptbahnhof", lat: 48.1851, lon: 16.3756, country: "AT" },
  wienWest: { stopId: "demo:wien-westbahnhof", name: "Wien Westbahnhof", lat: 48.1968, lon: 16.3378, country: "AT" },
  wienMitte: { stopId: "demo:wien-mitte", name: "Wien Mitte-Landstraße", lat: 48.2062, lon: 16.3846, country: "AT" },
  erdberg: { stopId: "demo:wien-erdberg", name: "Wien Erdberg", lat: 48.1913, lon: 16.4143, country: "AT" },
  schwedenplatz: { stopId: "demo:wien-schwedenplatz", name: "Wien Schwedenplatz", lat: 48.2118, lon: 16.3779, country: "AT" },
  flughafen: { stopId: "demo:flughafen-wien", name: "Flughafen Wien", lat: 48.1207, lon: 16.5631, country: "AT" },
  salzburg: { stopId: "demo:salzburg-hbf", name: "Salzburg Hauptbahnhof", lat: 47.8129, lon: 13.0458, country: "AT" },
  salzburgSued: { stopId: "demo:salzburg-sued", name: "Salzburg Süd P+R", lat: 47.7672, lon: 13.0694, country: "AT" },
  fuschl: { stopId: "demo:fuschl", name: "Fuschl am See Ortsmitte", lat: 47.7944, lon: 13.3046, country: "AT" },
  muenchen: { stopId: "demo:muenchen-hbf", name: "München Hauptbahnhof", lat: 48.1402, lon: 11.5583, country: "DE" },
  muenchenZob: { stopId: "demo:muenchen-zob", name: "München ZOB", lat: 48.1423, lon: 11.5495, country: "DE" },
};

export const PLACES = [
  { id: "wien", name: "Wien Stephansplatz" }, { id: "flughafen", name: "Flughafen Wien" }, { id: "salzburg", name: "Salzburg Hauptbahnhof" },
  { id: "fuschl", name: "Fuschl am See" }, { id: "muenchen", name: "München Hauptbahnhof" },
];

const DIRECTORY = [
  { id: "oebb", name: "ÖBB", country: "AT", aliases: ["Österreichische Bundesbahnen", "ÖBB-Personenverkehr", "OEBB"], modes: ["HIGHSPEED_RAIL", "REGIONAL_RAIL", "SUBURBAN"] },
  { id: "westbahn", name: "WESTbahn", country: "AT", aliases: ["WESTbahn Management"], modes: ["LONG_DISTANCE"] },
  { id: "wiener-linien", name: "Wiener Linien", country: "AT", aliases: [], modes: ["SUBWAY", "TRAM", "BUS"] },
  { id: "postbus", name: "Postbus", country: "AT", aliases: ["ÖBB-Postbus", "Österreichische Postbus"], modes: ["BUS"] },
  { id: "cat", name: "City Airport Train", country: "AT", aliases: ["CAT"], modes: ["REGIONAL_FAST_RAIL"] },
  { id: "vienna-airport-lines", name: "Vienna Airport Lines", country: "AT", aliases: [], modes: ["BUS"] },
  { id: "flixbus", name: "FlixBus", country: "DE", aliases: ["Flix", "FlixTrain"], modes: ["COACH"] },
  { id: "brb", name: "Bayerische Regiobahn", country: "DE", aliases: ["BRB"], modes: ["REGIONAL_FAST_RAIL"] },
  { id: "db-fernverkehr", name: "DB Fernverkehr", country: "DE", aliases: ["DB Fernverkehr AG"], modes: ["HIGHSPEED_RAIL"] },
  { id: "klimaticket", name: "KlimaTicket", country: "AT", aliases: ["One Mobility"], modes: [] },
  { id: "deutschlandticket", name: "Deutschlandticket", country: "DE", aliases: [], modes: [] },
];

// Rough outline of Vienna's city limits. The real zone is a stop list from the transport authority.
const VIENNA = [[16.18, 48.17], [16.2, 48.26], [16.29, 48.29], [16.37, 48.32], [16.46, 48.32], [16.55, 48.26],
  [16.58, 48.17], [16.52, 48.13], [16.44, 48.12], [16.35, 48.12], [16.22, 48.12]];
const SALZKAMMERGUT = [[13.0, 47.76], [13.0, 47.85], [13.2, 47.9], [13.6, 47.88], [13.75, 47.75], [13.6, 47.6], [13.25, 47.62], [13.05, 47.7]];

const AIRPORT_EXCEPT = [
  { operators: ["cat"], label: { de: "City Airport Train (CAT)", en: "City Airport Train (CAT)" } },
  { operators: ["vienna-airport-lines"], label: { de: "Flughafenbusse (Vienna Airport Lines)", en: "airport coaches (Vienna Airport Lines)" } },
];

export async function seed(store, now = Date.now()) {
  for (const entry of DIRECTORY) listOperator(store, entry);
  const known = (id) => store.data.operators[id];

  await saveProduct(store, known("klimaticket"), {
    id: "klimaticket.oesterreich", name: { de: "KlimaTicket Ö", en: "KlimaTicket Ö" }, sellable: false, template: "year",
    operators: "any", area: [{ type: "country", code: "AT" }], modes: { except: ["COACH", "AIRPLANE"] }, except: AIRPORT_EXCEPT,
    approximate: true, keywords: [["klimaticket", "klima ticket"]],
  }, now);
  await saveProduct(store, known("deutschlandticket"), {
    id: "deutschlandticket.d-ticket", name: { de: "Deutschlandticket", en: "Deutschlandticket" }, sellable: false, template: "month",
    timeZone: "Europe/Berlin", operators: "any",
    // Germany, plus the border stations it reaches on regional trains.
    area: [{ type: "country", code: "DE" }, { type: "stops", stops: [{ id: STOPS.salzburg.stopId, name: "Salzburg Hauptbahnhof", lat: STOPS.salzburg.lat, lon: STOPS.salzburg.lon }] }],
    modes: { except: ["HIGHSPEED_RAIL", "LONG_DISTANCE", "NIGHT_RAIL", "COACH", "AIRPLANE"] },
    personal: true, approximate: true, keywords: [["deutschlandticket", "deutschland ticket", "d ticket"]],
  }, now);
  for (const hours of [24, 72]) {
    await saveProduct(store, known("wiener-linien"), {
      id: `wiener-linien.${hours}-stunden-wien`, name: { de: `${hours}-Stunden-Ticket Wien`, en: `${hours} hours Vienna` }, sellable: false,
      template: "hours", params: { hours }, operators: "any",
      area: [{ type: "zone", id: "100", name: { de: "Wien (Kernzone 100)", en: "Vienna (core zone 100)" }, ring: VIENNA, approximate: true }],
      modes: { except: ["COACH", "AIRPLANE"] }, except: AIRPORT_EXCEPT, approximate: true,
      keywords: [[`${hours} stunden`, `${hours}h`, `${hours} hours`, `${hours} std`], ["wien", "vienna", "wiener linien"]],
    }, now);
  }

  const applied = applyOperator(store, {
    name: "Alpenland Bus", legalName: "Alpenland Bus GmbH (Beispiel)", country: "AT", level: "hosted", contactEmail: "vertrieb@alpenlandbus.example",
    registerNo: "FN 000000 x", vatId: "ATU00000000", modes: ["BUS"], commissionBps: 500, demo: true,
  }, now);
  const alpenland = await approveOperator(store, applied.operator.id, now);
  await saveProduct(store, alpenland, {
    name: { de: "Einzelfahrt", en: "Single ride" }, template: "single_route", params: { minutes: 120 }, price: { amount: 480, currency: "EUR" }, start: "chosen",
  }, now);
  await saveProduct(store, alpenland, {
    name: { de: "Tagesticket Salzkammergut", en: "Day ticket Salzkammergut" }, template: "day", price: { amount: 1290, currency: "EUR" }, start: "chosen",
    area: [{ type: "zone", id: "sk", name: { de: "Salzkammergut", en: "Salzkammergut" }, stops: [STOPS.salzburg.stopId, STOPS.fuschl.stopId], ring: SALZKAMMERGUT }],
  }, now);
  await saveProduct(store, alpenland, {
    name: { de: "24-Stunden-Netzticket", en: "24 hours network ticket" }, template: "hours", params: { hours: 24 }, price: { amount: 1690, currency: "EUR" },
  }, now);
  await saveProduct(store, alpenland, {
    name: { de: "Jahreskarte", en: "Annual pass" }, template: "year", price: { amount: 36500, currency: "EUR" }, start: "chosen",
  }, now);
  store.data.demo = { operatorKeys: { [alpenland.id]: applied.apiKey } };
  store.save();
}

function leg(mode, from, to, start, minutes, agencyName = null, routeShortName = null) {
  return {
    mode, from, to, startTime: new Date(start).toISOString(), endTime: new Date(start + minutes * 60000).toISOString(),
    duration: minutes * 60, ...(agencyName ? { agencyName, routeShortName } : {}),
  };
}

// [mode, from, to, minutes, operator, line]; a number alone is a wait in minutes.
const S = STOPS;
const ROUTES = {
  "wien|salzburg": [
    [["SUBWAY", S.stephansplatz, S.wienHbf, 5, "Wiener Linien", "U1"], 9, ["HIGHSPEED_RAIL", S.wienHbf, S.salzburg, 146, "ÖBB", "RJX 564"]],
    [["SUBWAY", S.stephansplatz, S.wienWest, 8, "Wiener Linien", "U3"], 12, ["LONG_DISTANCE", S.wienWest, S.salzburg, 150, "WESTbahn", "WB 912"]],
    [["SUBWAY", S.stephansplatz, S.erdberg, 7, "Wiener Linien", "U3"], 18, ["COACH", S.erdberg, S.salzburgSued, 185, "FlixBus", "N29"]],
  ],
  "wien|flughafen": [
    [["SUBWAY", S.stephansplatz, S.wienMitte, 2, "Wiener Linien", "U3"], 6, ["SUBURBAN", S.wienMitte, S.flughafen, 25, "ÖBB", "S7"]],
    [["SUBWAY", S.stephansplatz, S.wienMitte, 2, "Wiener Linien", "U3"], 8, ["REGIONAL_FAST_RAIL", S.wienMitte, S.flughafen, 16, "City Airport Train", "CAT"]],
    [["WALK", S.stephansplatz, S.schwedenplatz, 7], 5, ["BUS", S.schwedenplatz, S.flughafen, 22, "Vienna Airport Lines", "VAL 2"]],
  ],
  "wien|muenchen": [
    [["SUBWAY", S.stephansplatz, S.wienHbf, 5, "Wiener Linien", "U1"], 9, ["HIGHSPEED_RAIL", S.wienHbf, S.muenchen, 241, "ÖBB", "RJX 262"]],
    [["SUBWAY", S.stephansplatz, S.wienWest, 8, "Wiener Linien", "U3"], 12, ["LONG_DISTANCE", S.wienWest, S.salzburg, 150, "WESTbahn", "WB 912"], 14,
      ["REGIONAL_FAST_RAIL", S.salzburg, S.muenchen, 108, "Bayerische Regiobahn", "RE 5"]],
  ],
  "salzburg|muenchen": [
    [["REGIONAL_FAST_RAIL", S.salzburg, S.muenchen, 108, "Bayerische Regiobahn", "RE 5"]],
    [["HIGHSPEED_RAIL", S.salzburg, S.muenchen, 89, "ÖBB", "RJX 262"]],
    [["BUS", S.salzburg, S.salzburgSued, 14, "Postbus", "170"], 10, ["COACH", S.salzburgSued, S.muenchenZob, 115, "FlixBus", "N29"]],
  ],
  "salzburg|fuschl": [
    [["BUS", S.salzburg, S.fuschl, 38, "Alpenland Bus", "A15"]],
    [["BUS", S.salzburg, S.fuschl, 41, "Postbus", "150"]],
  ],
};

/** Sample connections in the shape MOTIS (and so the Publit apps) use for an itinerary. */
export function demoJourneys(from, to, time = Date.now()) {
  const patterns = ROUTES[`${from}|${to}`];
  if (!patterns) return [];
  const base = Math.ceil(time / 600000) * 600000 + 600000;
  return patterns.map((pattern, n) => {
    let clock = base + n * 420000;
    const legs = [];
    for (const step of pattern) {
      if (typeof step === "number") { clock += step * 60000; continue; }
      legs.push(leg(step[0], step[1], step[2], clock, step[3], step[4], step[5]));
      clock += step[3] * 60000;
    }
    const start = Date.parse(legs[0].startTime);
    return { startTime: legs[0].startTime, endTime: legs.at(-1).endTime, duration: (clock - start) / 1000,
      transfers: legs.filter((l) => l.mode !== "WALK").length - 1, legs };
  });
}

// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Answers one question: does this ticket cover this ride?
//
// A ticket's scope is data, not text (`validity`, written by the operator when the product is published):
//
//   timeZone   IANA zone the times are meant in
//   time       { type: "duration", minutes } | { type: "calendar", unit: "day"|"month"|"year", count }
//              | { type: "fixed", from, until }
//   rideOut    a ride begun before the end may be finished (default true)
//   operators  "any" or a list of operator ids whose vehicles accept it
//   modes      { only?: [...], except?: [...] } in MOTIS mode names (BUS, TRAM, SUBWAY, REGIONAL_RAIL, …)
//   area       list of rules; every stop of a ride must satisfy one of them (empty = no limit):
//                { type: "country", code }
//                { type: "zone", id, name, stops?: [stop ids], ring?: [[lon, lat], …], approximate? }
//                { type: "stops", stops: [{ id, name }] }
//                { type: "route", from?, to? }   between two stops; without them the pair chosen at purchase
//   except     list of { operators?, modes?, lines?, label }: rides that match are not covered
//   rides      "unlimited" or a number
//   approximate  true while the issuer has not confirmed this model (tickets recognised from a photo)
//
// The same function runs on the server (connection search) and on the conductor's device (offline check).

import { plain } from "./bytes.js";
import { pointInRing, distanceMeters, stopCountry } from "./geo.js";

const NO_TICKET = new Set(["WALK", "BIKE", "CAR", "CAR_PARKING", "CAR_DROPOFF", "RENTAL"]);

export function needsTicket(leg) {
  return !NO_TICKET.has(String(leg.mode ?? "").toUpperCase());
}

/** The operator of a ride: by id, else the directory entry whose longest alias is contained in the name. */
export function legOperator(leg, operators) {
  if (leg.operatorId && operators.some((o) => o.id === leg.operatorId)) return leg.operatorId;
  const words = new Set(plain(leg.agencyName ?? leg.operator ?? "").split(" ").filter(Boolean));
  if (words.size === 0) return null;
  let best = null;
  let bestScore = 0;
  for (const operator of operators) {
    for (const alias of [operator.name, ...(operator.aliases ?? [])]) {
      const parts = plain(alias).split(" ").filter(Boolean);
      if (parts.length === 0 || !parts.every((p) => words.has(p))) continue;
      const score = parts.length * 100 + parts.join("").length;
      if (score > bestScore) { best = operator.id; bestScore = score; }
    }
  }
  return best;
}

export function sameStop(a, b) {
  if (!a || !b) return false;
  const idA = a.stopId ?? a.id;
  const idB = b.stopId ?? b.id;
  if (idA && idB && idA === idB) return true;
  if (a.name && b.name && plain(a.name) === plain(b.name)) return true;
  if ([a.lat, a.lon, b.lat, b.lon].every((n) => typeof n === "number")) return distanceMeters(a, b) < 300;
  return false;
}

// true / false / null (cannot tell), and whether the answer rests on a rough outline.
function stopInRule(stop, rule) {
  switch (rule.type) {
    case "country": {
      const country = stopCountry(stop);
      if (!country) return { hit: null, approximate: false };
      return { hit: country.code === rule.code, approximate: country.approximate };
    }
    case "zone": {
      const id = stop.stopId ?? stop.id;
      if (id && rule.stops?.includes(id)) return { hit: true, approximate: false };
      if (rule.ring && typeof stop.lat === "number" && typeof stop.lon === "number") {
        return { hit: pointInRing(stop.lon, stop.lat, rule.ring), approximate: Boolean(rule.approximate) };
      }
      return { hit: rule.ring ? null : false, approximate: false };
    }
    case "stops":
      return { hit: rule.stops.some((s) => sameStop(stop, s)), approximate: false };
    default:
      return { hit: false, approximate: false };
  }
}

function areaCheck(leg, entitlement, inRoute) {
  const rules = entitlement.validity.area ?? [];
  if (rules.length === 0) return { hit: true, approximate: false };
  if (inRoute) return { hit: true, approximate: false };
  const places = rules.filter((r) => r.type !== "route");
  if (places.length === 0) return { hit: false, approximate: false, route: true };
  let approximate = false;
  let unknown = false;
  for (const stop of [leg.from, ...(leg.intermediateStops ?? []), leg.to]) {
    let hit = false;
    let stopUnknown = false;
    for (const rule of places) {
      const result = stopInRule(stop ?? {}, rule);
      if (result.hit) { hit = true; approximate ||= result.approximate; break; }
      if (result.hit === null) stopUnknown = true;
      approximate ||= result.approximate;
    }
    if (!hit && !stopUnknown) return { hit: false, approximate, stop };
    if (!hit) unknown = true;
  }
  return { hit: unknown ? null : true, approximate };
}

function excepted(leg, operatorId, validity) {
  const mode = String(leg.mode ?? "").toUpperCase();
  const line = plain(leg.routeShortName ?? leg.line ?? "");
  for (const rule of validity.except ?? []) {
    if (rule.operators && !rule.operators.includes(operatorId)) continue;
    if (rule.modes && !rule.modes.includes(mode)) continue;
    if (rule.lines && !rule.lines.some((l) => plain(l) === line)) continue;
    if (!rule.operators && !rule.modes && !rule.lines) continue;
    return rule;
  }
  return null;
}

/**
 * One ride against one ticket.
 * → { covered: true | false | null, reason, certainty: "exact" | "approximate", detail? }
 * `covered: null` means it cannot be told from the data (an operator that is not in the directory, a stop
 * without a position). `ms` are epoch milliseconds.
 */
export function coverLeg(leg, entitlement, context = {}, inRoute = false) {
  const validity = entitlement.validity;
  const base = { certainty: validity.approximate ? "approximate" : "exact" };
  if (!needsTicket(leg)) return { covered: true, reason: "no_ticket_needed", ...base };

  const start = Date.parse(leg.startTime);
  const end = Date.parse(leg.endTime ?? leg.startTime);
  if (Number.isFinite(start)) {
    if (start < entitlement.validFrom) return { covered: false, reason: "before_start", ...base };
    if (start > entitlement.validUntil) return { covered: false, reason: "after_end", ...base };
    if (end > entitlement.validUntil && validity.rideOut === false) return { covered: false, reason: "ends_after_end", ...base };
  }

  const mode = String(leg.mode ?? "").toUpperCase();
  if (validity.modes?.only && !validity.modes.only.includes(mode)) return { covered: false, reason: "mode", ...base };
  if (validity.modes?.except?.includes(mode)) return { covered: false, reason: "mode", ...base };

  const operatorId = legOperator(leg, context.operators ?? []);
  const rule = excepted(leg, operatorId, validity);
  if (rule) return { covered: false, reason: "excepted", detail: rule.label ?? null, ...base };

  if (Array.isArray(validity.operators)) {
    if (!operatorId) return { covered: null, reason: "operator_unknown", ...base };
    if (!validity.operators.includes(operatorId)) return { covered: false, reason: "operator", ...base };
  }

  const area = areaCheck(leg, entitlement, inRoute);
  const certainty = area.approximate || validity.approximate ? "approximate" : "exact";
  if (area.hit === false) return { covered: false, reason: area.route ? "route" : "area", detail: area.stop?.name ?? null, certainty };
  if (area.hit === null) return { covered: null, reason: "area_unknown", certainty };
  // "any operator" plus an operator nobody knows: the area says yes, but nobody confirmed that operator.
  if (!Array.isArray(validity.operators) && !operatorId && validity.approximate) {
    return { covered: null, reason: "operator_unknown", certainty: "approximate" };
  }
  return { covered: true, reason: "covered", certainty };
}

// For "route" tickets: the stretch of the journey between the ticket's two stops.
function routeRange(journey, entitlement) {
  const rule = (entitlement.validity.area ?? []).find((r) => r.type === "route");
  if (!rule) return null;
  const from = rule.from ?? entitlement.od?.from;
  const to = rule.to ?? entitlement.od?.to;
  if (!from || !to) return null;
  const legs = journey.legs ?? [];
  const first = legs.findIndex((l) => needsTicket(l) && sameStop(l.from, from));
  if (first < 0) return null;
  for (let last = legs.length - 1; last >= first; last -= 1) {
    if (needsTicket(legs[last]) && sameStop(legs[last].to, to)) return [first, last];
  }
  return null;
}

/**
 * A whole journey against the tickets someone holds.
 * → { status: "full" | "partial" | "none" | "unknown", legs: [{ index, needsTicket, covered, by, reason, … }] }
 */
export function coverJourney(journey, entitlements, context = {}) {
  const ranges = entitlements.map((e) => routeRange(journey, e));
  const legs = (journey.legs ?? []).map((leg, index) => {
    if (!needsTicket(leg)) return { index, needsTicket: false, covered: true, by: null, reason: "no_ticket_needed" };
    let best = null;
    for (let i = 0; i < entitlements.length; i += 1) {
      const range = ranges[i];
      const result = coverLeg(leg, entitlements[i], context, Boolean(range && index >= range[0] && index <= range[1]));
      if (result.covered === true) return { index, needsTicket: true, by: i, ...result };
      if (!best || (best.covered === false && result.covered === null)) best = { by: null, tried: i, ...result };
    }
    return { index, needsTicket: true, ...(best ?? { covered: false, by: null, reason: "no_ticket", certainty: "exact" }) };
  });
  const paid = legs.filter((l) => l.needsTicket);
  const yes = paid.filter((l) => l.covered === true).length;
  const unknown = paid.filter((l) => l.covered === null).length;
  let status = "partial";
  if (paid.length === yes) status = "full";
  else if (yes === 0 && unknown === 0) status = "none";
  else if (yes + unknown === paid.length) status = "unknown";
  return { status, legs, approximate: legs.some((l) => l.certainty === "approximate") };
}

/** MOTIS `transitModes` a router may use so it only looks for rides the ticket can cover at all. */
export function routerModes(validity) {
  const all = ["TRAM", "SUBWAY", "BUS", "COACH", "FERRY", "SUBURBAN", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL",
    "LONG_DISTANCE", "HIGHSPEED_RAIL", "NIGHT_RAIL", "FUNICULAR", "AERIAL_LIFT", "CABLE_CAR", "OTHER"];
  return all.filter((m) => (!validity.modes?.only || validity.modes.only.includes(m)) && !validity.modes?.except?.includes(m));
}

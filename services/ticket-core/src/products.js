// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Ticket products. An operator does not program anything: it picks a template (single ride, 24 hours, day,
// week, month, year), says where it applies and what it costs, and publishes. Every published change is a new
// version that never changes again; a ticket names the exact version it was sold under and carries the hash
// of its scope, so "where was this valid when I bought it" has one provable answer.

import { fingerprint } from "./core/bytes.js";
import { ROUGH_COUNTRIES } from "./core/geo.js";
import { ApiError, slug } from "./operators.js";

const MODES = ["TRAM", "SUBWAY", "BUS", "COACH", "FERRY", "SUBURBAN", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL",
  "LONG_DISTANCE", "HIGHSPEED_RAIL", "NIGHT_RAIL", "FUNICULAR", "AERIAL_LIFT", "CABLE_CAR", "AIRPLANE", "OTHER"];

export const TEMPLATES = [
  { id: "single", name: { de: "Einzelfahrt im Gebiet", en: "Single ride in an area" },
    params: { minutes: 90 }, time: (p) => ({ type: "duration", minutes: p.minutes ?? 90 }), rides: 1 },
  { id: "single_route", name: { de: "Einzelfahrt von A nach B", en: "Single ride from A to B" },
    params: { minutes: 240 }, time: (p) => ({ type: "duration", minutes: p.minutes ?? 240 }), rides: 1, route: true },
  { id: "hours", name: { de: "Stundenticket (24, 48, 72 Stunden)", en: "Hours pass (24, 48, 72 hours)" },
    params: { hours: 24 }, time: (p) => ({ type: "duration", minutes: (p.hours ?? 24) * 60 }) },
  { id: "day", name: { de: "Tagesticket (Kalendertag)", en: "Day ticket (calendar day)" },
    params: { days: 1, endHour: 0 }, time: (p) => ({ type: "calendar", unit: "day", count: p.days ?? 1, endHour: p.endHour ?? 0 }) },
  { id: "week", name: { de: "Wochenticket", en: "Weekly ticket" },
    params: {}, time: () => ({ type: "calendar", unit: "day", count: 7 }) },
  { id: "month", name: { de: "Monatsticket (Kalendermonat)", en: "Monthly ticket (calendar month)" },
    params: { months: 1 }, time: (p) => ({ type: "calendar", unit: "month", count: p.months ?? 1 }) },
  { id: "year", name: { de: "Jahres- oder Netzkarte", en: "Annual or network pass" },
    params: { years: 1 }, time: (p) => ({ type: "calendar", unit: "year", count: p.years ?? 1 }), personal: true },
];

function localName(value, field) {
  const out = typeof value === "string" ? { de: value, en: value } : value;
  if (!out || typeof out.de !== "string" || !out.de.trim() || out.de.length > 120) throw new ApiError(400, "invalid", `${field} is not valid`);
  return { de: out.de.trim(), en: typeof out.en === "string" && out.en.trim() ? out.en.trim().slice(0, 120) : out.de.trim() };
}

function stopRef(stop, field) {
  if (!stop || typeof stop !== "object" || (typeof stop.id !== "string" && typeof stop.name !== "string")) {
    throw new ApiError(400, "invalid", `${field} needs an id or a name`);
  }
  const out = {};
  if (typeof stop.id === "string") out.id = stop.id.slice(0, 120);
  if (typeof stop.name === "string") out.name = stop.name.slice(0, 120);
  if (typeof stop.lat === "number" && typeof stop.lon === "number") { out.lat = stop.lat; out.lon = stop.lon; }
  return out;
}

function ring(value) {
  if (!Array.isArray(value) || value.length < 3 || value.length > 2000) throw new ApiError(400, "invalid", "a zone outline needs 3 to 2000 points");
  return value.map((p) => {
    if (!Array.isArray(p) || typeof p[0] !== "number" || typeof p[1] !== "number" || Math.abs(p[0]) > 180 || Math.abs(p[1]) > 90) {
      throw new ApiError(400, "invalid", "outline points are [lon, lat]");
    }
    return [p[0], p[1]];
  });
}

function areaRule(rule) {
  switch (rule?.type) {
    case "country":
      if (!/^[A-Z]{2}$/.test(rule.code ?? "")) throw new ApiError(400, "invalid", "country rule needs a two-letter code");
      return { type: "country", code: rule.code };
    case "zone": {
      if (typeof rule.id !== "string" || !rule.id) throw new ApiError(400, "invalid", "zone rule needs an id");
      const out = { type: "zone", id: rule.id.slice(0, 60), name: typeof rule.name === "object" ? rule.name : String(rule.name ?? rule.id).slice(0, 120) };
      if (rule.stops) out.stops = rule.stops.filter((s) => typeof s === "string").slice(0, 20000);
      if (rule.ring) out.ring = ring(rule.ring);
      if (!out.stops && !out.ring) throw new ApiError(400, "invalid", "zone rule needs stops or an outline");
      if (rule.approximate) out.approximate = true;
      return out;
    }
    case "stops":
      if (!Array.isArray(rule.stops) || rule.stops.length === 0) throw new ApiError(400, "invalid", "stops rule needs stops");
      return { type: "stops", stops: rule.stops.slice(0, 20000).map((s) => stopRef(s, "stop")) };
    case "route": {
      const out = { type: "route" };
      if (rule.from) out.from = stopRef(rule.from, "from");
      if (rule.to) out.to = stopRef(rule.to, "to");
      return out;
    }
    default:
      throw new ApiError(400, "invalid", "area rule type must be country, zone, stops or route");
  }
}

function modeList(list, field) {
  if (list === undefined) return undefined;
  if (!Array.isArray(list) || !list.every((m) => MODES.includes(m))) throw new ApiError(400, "invalid", `${field} must use the mode names ${MODES.join(", ")}`);
  return list;
}

/** From what the operator typed to the scope every other part of the system reads. */
export function buildValidity(operator, input) {
  const template = TEMPLATES.find((t) => t.id === input.template);
  if (!template) throw new ApiError(400, "invalid", `template must be one of ${TEMPLATES.map((t) => t.id).join(", ")}`);
  const params = input.params ?? {};
  for (const value of Object.values(params)) {
    if (!Number.isInteger(value) || value < 0 || value > 100000) throw new ApiError(400, "invalid", "params must be whole numbers");
  }
  const area = (Array.isArray(input.area) ? input.area : []).map(areaRule);
  if (template.route && !area.some((r) => r.type === "route")) area.push({ type: "route" });
  const operators = input.operators === "any" ? "any" : Array.isArray(input.operators) && input.operators.length
    ? input.operators.filter((o) => typeof o === "string").slice(0, 500) : [operator.id];
  const validity = {
    timeZone: typeof input.timeZone === "string" ? input.timeZone : "Europe/Vienna",
    time: input.time ?? template.time(params),
    rideOut: input.rideOut !== false,
    operators,
    area,
    rides: template.rides ?? "unlimited",
    class: input.class === 1 ? 1 : 2,
    personal: input.personal ?? template.personal ?? false,
  };
  try {
    new Intl.DateTimeFormat("en", { timeZone: validity.timeZone });
  } catch {
    throw new ApiError(400, "invalid", "timeZone is not a known IANA zone");
  }
  const only = modeList(input.modes?.only, "modes.only");
  const except = modeList(input.modes?.except, "modes.except");
  if (only || except) validity.modes = { ...(only ? { only } : {}), ...(except ? { except } : {}) };
  if (Array.isArray(input.except) && input.except.length) {
    validity.except = input.except.slice(0, 200).map((rule) => ({
      ...(Array.isArray(rule.operators) ? { operators: rule.operators.filter((o) => typeof o === "string") } : {}),
      ...(rule.modes ? { modes: modeList(rule.modes, "except.modes") } : {}),
      ...(Array.isArray(rule.lines) ? { lines: rule.lines.filter((l) => typeof l === "string") } : {}),
      ...(rule.label ? { label: rule.label } : {}),
    }));
  }
  if (input.approximate) validity.approximate = true;
  return validity;
}

/** What goes out to apps: one version of a product. */
export function productView(product, version = currentVersion(product)) {
  return {
    id: product.id, operatorId: product.operatorId, sellable: product.sellable, version: version.version,
    status: version.status, name: version.name, template: version.template, price: version.price,
    start: version.start, needs: version.needs, validity: version.validity, hash: version.hash,
    keywords: version.keywords, publishedAt: version.publishedAt,
  };
}

export function currentVersion(product) {
  return product.versions.findLast((v) => v.status === "published") ?? product.versions.at(-1);
}

export function findVersion(store, productId, version) {
  const product = store.data.products[productId];
  const found = product?.versions.find((v) => v.version === version);
  return found ? { product, version: found } : null;
}

/**
 * Creates a product or, when it exists, a new version of it. `draft: true` keeps it out of the sale until
 * `publishProduct`. Third-party tickets we only recognise (KlimaTicket, …) are stored with `sellable: false`.
 */
export async function saveProduct(store, operator, input, now = Date.now()) {
  const name = localName(input.name, "name");
  const id = input.id ?? `${operator.id}.${slug(name.de)}`;
  if (!/^[a-z0-9.-]{3,100}$/.test(id) || !id.startsWith(`${operator.id}.`)) throw new ApiError(400, "invalid", "product id must start with the operator id");
  const sellable = input.sellable !== false;
  let price = null;
  if (sellable) {
    if (!Number.isInteger(input.price?.amount) || input.price.amount < 0 || input.price.amount > 10000000 || !/^[A-Z]{3}$/.test(input.price?.currency ?? "")) {
      throw new ApiError(400, "invalid", "price needs amount (in cents) and currency");
    }
    price = { amount: input.price.amount, currency: input.price.currency };
  } else if (input.price) {
    price = { amount: input.price.amount, currency: input.price.currency };
  }
  const validity = buildValidity(operator, input);
  const needs = [];
  if (validity.area.some((r) => r.type === "route" && (!r.from || !r.to))) needs.push("od");
  if (validity.personal) needs.push("holder");
  const product = store.data.products[id] ??= { id, operatorId: operator.id, sellable, versions: [] };
  if (product.operatorId !== operator.id) throw new ApiError(403, "forbidden", "this product belongs to another operator");
  const version = {
    version: product.versions.length + 1, status: input.draft ? "draft" : "published", name, template: input.template,
    price, start: input.start === "chosen" ? "chosen" : "purchase", needs, validity, hash: await fingerprint(validity),
    keywords: Array.isArray(input.keywords) ? input.keywords : null, publishedAt: input.draft ? null : now,
    ...(input.review ? { review: input.review } : {}),
  };
  if (!input.draft) for (const old of product.versions) if (old.status === "published") old.status = "replaced";
  product.versions.push(version);
  store.save();
  return { product, version };
}

export function publishProduct(store, operator, productId, now = Date.now()) {
  const product = store.data.products[productId];
  if (!product || product.operatorId !== operator.id) throw new ApiError(404, "not_found", "no such product");
  const draft = product.versions.findLast((v) => v.status === "draft");
  if (!draft) throw new ApiError(409, "no_draft", "nothing to publish");
  for (const old of product.versions) if (old.status === "published") old.status = "replaced";
  draft.status = "published";
  draft.publishedAt = now;
  store.save();
  return { product, version: draft };
}

export function retireProduct(store, operator, productId) {
  const product = store.data.products[productId];
  if (!product || product.operatorId !== operator.id) throw new ApiError(404, "not_found", "no such product");
  for (const version of product.versions) if (version.status === "published" || version.status === "draft") version.status = "retired";
  store.save();
  return product;
}

/** The scope as GeoJSON, for a map in the app. */
export function areaGeoJson(validity) {
  const features = [];
  for (const rule of validity.area ?? []) {
    if (rule.ring) {
      features.push({ type: "Feature", properties: { kind: "zone", id: rule.id, name: rule.name, approximate: Boolean(rule.approximate) },
        geometry: { type: "Polygon", coordinates: [[...rule.ring, rule.ring[0]]] } });
    }
    const stops = rule.type === "stops" ? rule.stops : rule.type === "route" ? [rule.from, rule.to].filter(Boolean) : [];
    for (const stop of stops) {
      if (typeof stop.lat !== "number") continue;
      features.push({ type: "Feature", properties: { kind: "stop", name: stop.name ?? stop.id }, geometry: { type: "Point", coordinates: [stop.lon, stop.lat] } });
    }
    if (rule.type === "country") {
      const rough = ROUGH_COUNTRIES[rule.code];
      features.push({ type: "Feature", properties: { kind: "country", code: rule.code, approximate: true },
        geometry: rough ? { type: "Polygon", coordinates: [[...rough, rough[0]]] } : null });
    }
  }
  return { type: "FeatureCollection", features };
}

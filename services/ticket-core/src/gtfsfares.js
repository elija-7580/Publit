// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Import from GTFS-Fares v2, the fare tables many operators already publish next to their timetable
// (https://gtfs.org/documentation/schedule/examples/fares-v2/). Each fare product becomes a draft product
// here: price and area come from the feed, the time rule is guessed from the name and listed under `review`
// so the operator confirms it before it goes on sale.
//
// Input: the feed's text files by name, e.g. { "fare_products.txt": "…", "fare_leg_rules.txt": "…",
// "areas.txt": "…", "stop_areas.txt": "…", "stops.txt": "…", "fare_transfer_rules.txt": "…" }.

import { ApiError } from "./operators.js";
import { saveProduct } from "./products.js";

export function parseCsv(text) {
  const rows = [];
  let row = [];
  let cell = "";
  let quoted = false;
  const source = String(text).replace(/^﻿/, "");
  for (let i = 0; i < source.length; i += 1) {
    const c = source[i];
    if (quoted) {
      if (c === '"' && source[i + 1] === '"') { cell += '"'; i += 1; } else if (c === '"') quoted = false; else cell += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") { row.push(cell); cell = ""; } else if (c === "\n" || c === "\r") {
      if (c === "\r" && source[i + 1] === "\n") i += 1;
      row.push(cell); cell = "";
      if (row.some((v) => v !== "")) rows.push(row);
      row = [];
    } else cell += c;
  }
  row.push(cell);
  if (row.some((v) => v !== "")) rows.push(row);
  if (rows.length === 0) return [];
  const header = rows[0].map((h) => h.trim());
  return rows.slice(1).map((r) => Object.fromEntries(header.map((h, i) => [h, (r[i] ?? "").trim()])));
}

function guessTime(name, transferMinutes) {
  const n = name.toLowerCase();
  const hours = /(\d{1,3})\s*(?:h\b|std|stunden|hours?)/.exec(n);
  if (hours) return { template: "hours", params: { hours: Number(hours[1]) }, guess: `${hours[1]} hours, from the name` };
  if (/jahr|annual|year/.test(n)) return { template: "year", params: {}, guess: "one year, from the name" };
  if (/monat|month/.test(n)) return { template: "month", params: {}, guess: "calendar month, from the name" };
  if (/woche|week/.test(n)) return { template: "week", params: {}, guess: "seven days, from the name" };
  if (/tag|day/.test(n)) return { template: "day", params: {}, guess: "calendar day, from the name" };
  if (transferMinutes) return { template: "single", params: { minutes: transferMinutes }, guess: `single ride, ${transferMinutes} minutes from the feed's transfer rule` };
  return { template: "single", params: { minutes: 90 }, guess: "single ride, 90 minutes assumed (the feed gives no duration)" };
}

export async function importGtfsFares(store, operator, files, now = Date.now()) {
  if (!files || typeof files["fare_products.txt"] !== "string") throw new ApiError(400, "invalid", "fare_products.txt is missing");
  const table = (name) => (typeof files[name] === "string" ? parseCsv(files[name]) : []);
  const products = table("fare_products.txt");
  const legRules = table("fare_leg_rules.txt");
  const areaNames = Object.fromEntries(table("areas.txt").map((a) => [a.area_id, a.area_name || a.area_id]));
  const stops = Object.fromEntries(table("stops.txt").map((s) => [s.stop_id, s]));
  const areaStops = {};
  for (const row of table("stop_areas.txt")) (areaStops[row.area_id] ??= []).push(row.stop_id);
  const transfer = table("fare_transfer_rules.txt").map((r) => Number(r.duration_limit)).filter((n) => n > 0);
  const transferMinutes = transfer.length ? Math.round(Math.max(...transfer) / 60) : null;

  const seen = new Set();
  const created = [];
  for (const row of products.slice(0, 500)) {
    const id = row.fare_product_id;
    const amount = Math.round(Number(row.amount) * 100);
    if (!id || seen.has(id) || !Number.isFinite(amount) || !/^[A-Z]{3}$/.test(row.currency ?? "")) continue;
    seen.add(id);
    const name = row.fare_product_name || id;
    const areas = new Set();
    let everywhere = false;
    for (const rule of legRules.filter((r) => r.fare_product_id === id)) {
      if (!rule.from_area_id && !rule.to_area_id) everywhere = true;
      for (const area of [rule.from_area_id, rule.to_area_id]) if (area) areas.add(area);
    }
    const time = guessTime(name, transferMinutes);
    const review = [`Time rule: ${time.guess}.`];
    const area = [];
    if (!everywhere) {
      for (const areaId of areas) {
        const ids = areaStops[areaId] ?? [];
        if (ids.length === 0) { review.push(`Area ${areaId} has no stops in stop_areas.txt and was left out.`); continue; }
        area.push({ type: "zone", id: areaId, name: areaNames[areaId] ?? areaId, stops: ids });
      }
      if (areas.size > 1) review.push("The feed prices rides between areas; here the ticket covers rides within all of them together.");
    }
    if (area.length === 0) review.push("No area limit: valid on the operator's whole network.");
    const { product, version } = await saveProduct(store, operator, {
      id: `${operator.id}.${id.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "product"}`,
      name, template: time.template, params: time.params, price: { amount, currency: row.currency }, area, draft: true, review,
    }, now);
    created.push({ id: product.id, version: version.version, name: version.name, price: version.price, review,
      stopsKnown: Object.keys(stops).length > 0 });
  }
  if (created.length === 0) throw new ApiError(400, "invalid", "no usable rows in fare_products.txt");
  return created;
}

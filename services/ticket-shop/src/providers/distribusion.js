// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Distribusion Retailer API v4: intercity bus, rail, ferry and airport transfers in many European countries.
// Written against the public documentation at https://docs.distribusion.com/dt/api (search, reservation,
// confirmation, tickets). Needs DISTRIBUSION_API_KEY (and DISTRIBUSION_BASE_URL for production, see README).
// Publit takes the payment itself and confirms with execute_payment=false; Distribusion invoices the ticket
// price minus commission once a month.

import { ProviderError } from "./errors.js";

const DEMO_BASE = "https://api.demo.distribusion.com/retailers/v4";
/** Transitous / MOTIS modes that Distribusion sells: long-distance bus, trains and ferries. */
const MODES = new Set(["COACH", "BUS", "RAIL", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL", "LONG_DISTANCE", "HIGHSPEED_RAIL",
  "NIGHT_RAIL", "FERRY"]);
/** Departure must match the leg within this many minutes, arrival within twice that. */
const TIME_SLACK_MIN = 6;
const ADULT = "PNOS";

function base(env) {
  return (env.DISTRIBUSION_BASE_URL || DEMO_BASE).replace(/\/+$/, "");
}

async function call(env, method, path, body, fetchImpl = fetch) {
  const response = await fetchImpl(`${base(env)}${path}`, {
    method,
    headers: {
      "Api-Key": env.DISTRIBUSION_API_KEY,
      "Content-Type": "application/json",
      Accept: "application/vnd.api+json, application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { /* not JSON */ }
  if (!response.ok) {
    const detail = json?.errors?.[0]?.detail ?? json?.errors?.[0]?.title ?? `HTTP ${response.status}`;
    throw new ProviderError("distribusion", response.status, String(detail).slice(0, 200));
  }
  return json;
}

function geo(place) {
  return { type: "geo", value: `${Number(place.lat).toFixed(6)},${Number(place.lon).toFixed(6)}`, radius: 1500 };
}

/** "2026-12-01T08:15" in the station's local time, as Distribusion writes it, compared as UTC minutes via offset. */
function minutesApart(isoA, isoB) {
  const a = Date.parse(isoA), b = Date.parse(isoB);
  if (Number.isNaN(a) || Number.isNaN(b)) return Infinity;
  return Math.abs(a - b) / 60000;
}

/** Local date (YYYY-MM-DD) of the departure in the leg's time zone, else in UTC. */
function localDate(iso, timeZone) {
  const date = new Date(iso);
  try {
    return new Intl.DateTimeFormat("en-CA", { timeZone: timeZone || "UTC", year: "numeric", month: "2-digit", day: "2-digit" }).format(date);
  } catch {
    return date.toISOString().slice(0, 10);
  }
}

function included(json, type, id) {
  return (json?.included ?? []).find((item) => item.type === type && item.id === id);
}

function relId(item, name) {
  const data = item?.relationships?.[name]?.data;
  return Array.isArray(data) ? data.map((d) => d.id) : data?.id;
}

/** Distribusion returns local times without an offset; MOTIS gives UTC. Converts a local wall time to an instant. */
function instant(local, timeZone) {
  if (!local) return null;
  if (/[zZ]|[+-]\d{2}:?\d{2}$/.test(local)) return new Date(local).toISOString();
  const guess = new Date(`${local}Z`);
  if (!timeZone) return guess.toISOString();
  try {
    const parts = new Intl.DateTimeFormat("en-US", { timeZone, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit",
      hour: "2-digit", minute: "2-digit", second: "2-digit" }).formatToParts(guess);
    const get = (t) => Number(parts.find((p) => p.type === t)?.value);
    const asLocal = Date.UTC(get("year"), get("month") - 1, get("day"), get("hour"), get("minute"), get("second"));
    return new Date(guess.getTime() - (asLocal - guess.getTime())).toISOString();
  } catch {
    return guess.toISOString();
  }
}

export const distribusion = {
  id: "distribusion",
  name: "Distribusion",

  enabled(env) {
    return typeof env.DISTRIBUSION_API_KEY === "string" && env.DISTRIBUSION_API_KEY.length > 0;
  },

  covers(leg) {
    return MODES.has(String(leg.mode ?? "").toUpperCase());
  },

  /** Connections that are this leg (same departure and arrival time near the same places), cheapest fare each. */
  async offers(leg, request, env, fetchImpl = fetch) {
    const adults = request.adults;
    const body = {
      currency: request.currency,
      locale: request.locale,
      departure_date: localDate(leg.departure, leg.from.tz),
      pax: adults,
      search_bounds: [{ departure_location: geo(leg.from), arrival_location: geo(leg.to),
        departure_date: localDate(leg.departure, leg.from.tz), is_requested: true }],
      include: ["fares", "stations", "marketing_carriers", "fare_classes", "fare_conditions"],
      number_of_connections: 20,
    };
    const json = await call(env, "POST", "/connections/find", body, fetchImpl);
    const out = [];
    for (const connection of json?.data ?? []) {
      const a = connection.attributes ?? {};
      const fromStation = included(json, "stations", relId(connection, "departure_station"));
      const toStation = included(json, "stations", relId(connection, "arrival_station"));
      const departure = instant(a.departure_time, fromStation?.attributes?.time_zone ?? leg.from.tz);
      const arrival = instant(a.arrival_time, toStation?.attributes?.time_zone ?? leg.to.tz);
      if (minutesApart(departure, leg.departure) > TIME_SLACK_MIN) continue;
      if (minutesApart(arrival, leg.arrival) > TIME_SLACK_MIN * 2) continue;
      if (a.booked_out) continue;
      const carrierId = relId(connection, "marketing_carrier");
      const carrier = included(json, "marketing_carriers", carrierId);
      const fares = (relId(connection, "fares") ?? []).map((id) => included(json, "fares", id)).filter(Boolean)
        .filter((f) => !f.attributes?.booked_out && Number.isFinite(f.attributes?.price));
      fares.sort((x, y) => x.attributes.price - y.attributes.price);
      const fare = fares[0];
      if (!fare) continue;
      const fareClass = included(json, "fare_classes", relId(fare, "fare_class"));
      const condition = included(json, "fare_conditions", relId(fare, "fare_conditions"));
      out.push({
        title: fareClass?.attributes?.name ?? "Ticket",
        operator: carrier?.attributes?.trade_name ?? leg.operator ?? null,
        amount: fare.attributes.price,
        currency: json?.meta?.currency ?? request.currency,
        refundable: condition?.attributes?.refundable ?? null,
        data: {
          carrier: carrier?.attributes?.code ?? carrierId,
          from: fromStation?.attributes?.code ?? relId(connection, "departure_station"),
          to: toStation?.attributes?.code ?? relId(connection, "arrival_station"),
          fromName: fromStation?.attributes?.name ?? leg.from.name,
          toName: toStation?.attributes?.name ?? leg.to.name,
          departure: a.departure_time,
          arrival: a.arrival_time,
          departureAt: departure,
          arrivalAt: arrival,
          fareClass: fareClass?.attributes?.code ?? a.cheapest_fare_class_code,
          offerId: fare.attributes.offer_id ?? null,
          adults,
          currency: json?.meta?.currency ?? request.currency,
          locale: request.locale,
        },
      });
      break;
    }
    return out;
  },

  async reserve(data, customer, env, fetchImpl = fetch) {
    const passengers = Array.from({ length: data.adults }, (_, i) => ({
      id: String(i + 1),
      type: ADULT,
      ...(i === 0 ? { first_name: customer.firstName, last_name: customer.lastName } : {}),
    }));
    const body = {
      marketing_carrier: data.carrier,
      departure_station: data.from,
      arrival_station: data.to,
      departure_time: data.departure,
      arrival_time: data.arrival,
      fare_class: data.fareClass,
      currency: data.currency,
      locale: data.locale,
      passengers,
      first_name: customer.firstName,
      last_name: customer.lastName,
      email: customer.email,
      terms_accepted: true,
    };
    if (data.offerId) body.offers = [{ id: data.offerId, passenger_ids: passengers.map((p) => p.id) }];
    const json = await call(env, "POST", "/reservations/create", body, fetchImpl);
    const r = json?.data;
    if (!r?.id || !Number.isFinite(r.attributes?.total_price)) throw new ProviderError("distribusion", 502, "No reservation");
    return {
      ref: { id: r.id, carrier: data.carrier, adults: data.adults },
      amount: r.attributes.total_price,
      currency: json?.meta?.currency ?? data.currency,
      expiresAt: r.attributes.expires_at ?? null,
    };
  },

  async confirm(ref, customer, env, fetchImpl = fetch) {
    const passengers = Array.from({ length: ref.adults ?? 1 }, (_, i) => ({
      id: String(i + 1),
      type: ADULT,
      first_name: customer.firstName,
      last_name: customer.lastName,
    }));
    try {
      const json = await call(env, "PUT", "/reservations/confirm", {
        reservation_id: ref.id,
        marketing_carrier: ref.carrier,
        send_customer_email: true,
        execute_payment: false,
        payment_method: "demand_note",
        first_name: customer.firstName,
        last_name: customer.lastName,
        email: customer.email,
        terms_accepted: true,
        passengers,
      }, fetchImpl);
      const booking = relId(json?.data, "booking");
      return { booking: booking ?? null, reservation: ref.id };
    } catch (error) {
      // A repeated confirmation (the app retried) is not a failure when the reservation is already booked.
      const json = await call(env, "GET", `/reservations/${encodeURIComponent(ref.id)}`, null, fetchImpl).catch(() => null);
      if (json?.data?.attributes?.state === "confirmed") return { booking: relId(json.data, "booking") ?? null, reservation: ref.id };
      throw error;
    }
  },

  async tickets(booking, env, fetchImpl = fetch) {
    if (!booking?.booking) return [];
    const response = await fetchImpl(`${base(env)}/bookings/${encodeURIComponent(booking.booking)}/tickets?type=pdf`, {
      headers: { "Api-Key": env.DISTRIBUSION_API_KEY, Accept: "application/pdf" },
    });
    if (!response.ok) throw new ProviderError("distribusion", response.status, "Ticket not ready");
    const bytes = new Uint8Array(await response.arrayBuffer());
    let binary = "";
    for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    return [{ pdf: btoa(binary), reference: booking.booking }];
  },

  async cancel(ref, env, fetchImpl = fetch) {
    await call(env, "PUT", "/reservations/cancel", { reservation_id: ref.id }, fetchImpl).catch(() => {});
  },
};

export const _test = { instant, localDate, minutesApart };

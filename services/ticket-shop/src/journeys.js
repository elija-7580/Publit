// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Router plus ticket in one call: connections from Publit's own MOTIS server (services/routing), and for every
// leg the ticket that can be bought here (offer) or, failing that, the best place to buy it (link).
//
//   POST /v1/journeys  { from: { lat, lon, stopId?, name? }, to: {…}, time?, arriveBy?, results?,
//                        adults?, currency?, locale?, app? }
//                    → { journeys: [{ departure, arrival, duration, transfers, legs, offers, links, total }] }
//
// Only a router on ROUTER_URL is asked. Transitous' public API (and the MOTIS servers behind it) may not be used
// commercially, so they are refused here; without an own router this endpoint answers 503.

import { ShopError, findOffers } from "./shop.js";
import { findLinks } from "./links.js";

const NON_COMMERCIAL_ROUTERS = ["transitous.org", "motis-project.de"];
const TRANSIT = new Set(["TRAM", "SUBWAY", "FERRY", "AIRPLANE", "BUS", "COACH", "RAIL", "HIGHSPEED_RAIL",
  "LONG_DISTANCE", "NIGHT_RAIL", "REGIONAL_FAST_RAIL", "REGIONAL_RAIL", "SUBURBAN", "METRO", "FUNICULAR",
  "CABLE_CAR", "AERIAL_LIFT", "ODM", "TRANSIT"]);
const MAX_RESULTS = 5;

function hostIn(host, list) {
  return list.some((h) => host === h || host.endsWith("." + h));
}

/** The own router's address, or a 503 when none is set (or it points to a non-commercial service). */
export function routerURL(env) {
  let url;
  try {
    url = new URL(env.ROUTER_URL ?? "");
  } catch {
    throw new ShopError(503, "not_configured", "No own router configured (ROUTER_URL)");
  }
  if (url.protocol !== "https:" && url.hostname !== "localhost" && url.hostname !== "127.0.0.1") {
    throw new ShopError(503, "not_configured", "ROUTER_URL must be https");
  }
  if (hostIn(url.hostname.toLowerCase(), NON_COMMERCIAL_ROUTERS)) {
    throw new ShopError(503, "not_configured", "This router may not be used commercially; set up an own one");
  }
  return url;
}

function point(value, name) {
  if (!value || typeof value !== "object") throw new ShopError(400, "invalid", `${name} missing`);
  const stopId = typeof value.stopId === "string" && value.stopId.length <= 200 ? value.stopId : null;
  const lat = Number(value.lat), lon = Number(value.lon);
  const hasCoordinate = Number.isFinite(lat) && Number.isFinite(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180;
  if (!stopId && !hasCoordinate) throw new ShopError(400, "invalid", `${name}: stopId or lat/lon`);
  return stopId ?? `${lat},${lon}`;
}

export function parseJourneyRequest(body) {
  if (!body || typeof body !== "object") throw new ShopError(400, "invalid", "Invalid request");
  const time = body.time === undefined ? null : String(body.time);
  if (time !== null && Number.isNaN(Date.parse(time))) throw new ShopError(400, "invalid", "time: ISO 8601");
  const results = body.results === undefined ? 3 : Number(body.results);
  if (!Number.isInteger(results) || results < 1 || results > MAX_RESULTS) {
    throw new ShopError(400, "invalid", `results: 1 to ${MAX_RESULTS}`);
  }
  return {
    from: point(body.from, "from"),
    to: point(body.to, "to"),
    time,
    arriveBy: body.arriveBy === true,
    results,
    adults: body.adults,
    currency: body.currency,
    locale: body.locale,
    app: body.app,
  };
}

function place(p) {
  return { name: p?.name ?? "", lat: p?.lat, lon: p?.lon, stopId: p?.stopId ?? null, tz: p?.tz ?? null };
}

/** MOTIS itinerary → the journey shape of this API (transit legs keep their index in the itinerary). */
export function journeyFrom(itinerary) {
  const legs = (itinerary.legs ?? []).map((leg, index) => ({
    index,
    mode: leg.mode,
    transit: TRANSIT.has(leg.mode),
    line: leg.displayName ?? leg.routeShortName ?? null,
    operator: leg.agencyName ?? null,
    headsign: leg.headsign ?? null,
    from: place(leg.from),
    to: place(leg.to),
    departure: leg.startTime,
    arrival: leg.endTime,
    links: { booking: leg.ticketUrls?.web ?? null, fares: leg.agencyFareUrl ?? null, website: leg.agencyUrl ?? null },
  }));
  return {
    departure: itinerary.startTime,
    arrival: itinerary.endTime,
    duration: itinerary.duration,
    transfers: itinerary.transfers ?? Math.max(0, legs.filter((l) => l.transit).length - 1),
    legs,
  };
}

/** Sum of the offers when every transit leg has one in the same currency, else null (buy the rest elsewhere). */
export function total(journey, offers) {
  const transit = journey.legs.filter((l) => l.transit);
  if (transit.length === 0 || offers.length !== transit.length) return null;
  const currency = offers[0].currency;
  if (offers.some((o) => o.currency !== currency)) return null;
  return { amount: offers.reduce((sum, o) => sum + o.amount, 0), currency };
}

export async function findJourneys(body, env, { fetchImpl = fetch, list } = {}) {
  const request = parseJourneyRequest(body);
  const base = routerURL(env);
  const plan = new URL("/api/v6/plan", base);
  plan.searchParams.set("fromPlace", request.from);
  plan.searchParams.set("toPlace", request.to);
  if (request.time) plan.searchParams.set("time", request.time);
  if (request.arriveBy) plan.searchParams.set("arriveBy", "true");
  plan.searchParams.set("numItineraries", String(request.results));
  let response;
  try {
    response = await fetchImpl(plan.toString(), { headers: { Accept: "application/json", "User-Agent": "Publit ticket shop" } });
  } catch {
    throw new ShopError(502, "router", "Router not reachable");
  }
  if (!response.ok) throw new ShopError(502, "router", `Router answered ${response.status}`);
  const data = await response.json();
  const journeys = (data.itineraries ?? []).slice(0, request.results).map(journeyFrom);

  return {
    journeys: await Promise.all(journeys.map(async (journey) => {
      const transit = journey.legs.filter((l) => l.transit);
      let offers = [];
      if (transit.length > 0 && env.TOKEN_SECRET) {
        const legs = transit.map((l) => ({ index: l.index, mode: l.mode, line: l.line, operator: l.operator,
          from: l.from, to: l.to, departure: l.departure, arrival: l.arrival }));
        try {
          const options = list ? { list, fetchImpl } : { fetchImpl };
          offers = (await findOffers({ legs, adults: request.adults, currency: request.currency, locale: request.locale },
            env, options)).offers;
        } catch (error) {
          if (!(error instanceof ShopError)) throw error; // a leg the shop cannot price is simply bought elsewhere
        }
      }
      const sold = new Set(offers.map((o) => o.leg));
      const rest = transit.filter((l) => !sold.has(l.index));
      const links = rest.length === 0 ? [] : findLinks({
        legs: rest.map((l) => ({ index: l.index, operator: l.operator ?? "", mode: l.mode, links: l.links,
          from: l.from?.name, to: l.to?.name, departure: l.departure, timeZone: l.from?.tz ?? undefined })),
        ...(request.app ? { app: request.app } : {}),
      }, env).links;
      return { ...journey, offers, links, total: total(journey, offers) };
    })),
  };
}

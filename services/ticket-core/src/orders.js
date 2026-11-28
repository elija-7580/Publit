// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Orders, tickets, refunds, inspections and the monthly statement.
//
// Ticket payload (what the QR code carries, signed by the issuer):
//   v    format version            id   ticket number           iss  issuer (operator id)   kid  signing key
//   p    product id                pv   product version         vh   hash of that version's scope
//   nbf  first valid second        exp  last valid second       iat  issued at
//   n    number of travellers      cls  class
//   od   { from, to } stops        for tickets between two stops
//   hn   holder's name, hb year of birth     for personal passes (checked against an ID)
//   dk   device key                when set, the code must be shown live by that device (no screenshots)

import { randomBytes } from "node:crypto";
import { signTicket } from "./core/token.js";
import { resolveWindow } from "./core/time.js";
import { ApiError } from "./operators.js";
import { currentVersion } from "./products.js";

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function id(prefix, length = 10) {
  let out = prefix;
  for (const b of randomBytes(length)) out += ALPHABET[b % 32];
  return out;
}

function stop(value, field) {
  if (!value || typeof value !== "object" || (typeof value.id !== "string" && typeof value.name !== "string")) {
    throw new ApiError(400, "invalid", `${field} needs an id or a name`);
  }
  const out = {};
  if (typeof value.id === "string") out.id = value.id.slice(0, 120);
  if (typeof value.name === "string") out.name = value.name.slice(0, 80);
  if (typeof value.lat === "number" && typeof value.lon === "number") { out.lat = Number(value.lat.toFixed(5)); out.lon = Number(value.lon.toFixed(5)); }
  return out;
}

/** Step 1: the buyer chose a product. Nothing is issued yet. */
export function createOrder(store, input, now = Date.now()) {
  const product = store.data.products[input.productId];
  const version = product && currentVersion(product);
  if (!product || !product.sellable || version.status !== "published") throw new ApiError(404, "not_found", "this product is not on sale");
  const operator = store.data.operators[product.operatorId];
  if (operator.status !== "active") throw new ApiError(409, "operator_inactive", "this operator is not selling at the moment");
  if (!operator.keys.some((k) => k.status === "active" && k.privateJwk)) {
    throw new ApiError(409, "operator_issues", "this operator issues its own tickets; the sale goes through its own system");
  }
  let start = now;
  if (input.start !== undefined && input.start !== null) {
    start = Date.parse(input.start);
    if (!Number.isFinite(start) || start < now - 300000 || start > now + 366 * 86400000) throw new ApiError(400, "invalid", "start must be between now and one year from now");
    if (version.start !== "chosen" && Math.abs(start - now) > 300000) throw new ApiError(400, "invalid", "this ticket starts at purchase");
  }
  const travellers = input.travellers ?? 1;
  if (!Number.isInteger(travellers) || travellers < 1 || travellers > 9) throw new ApiError(400, "invalid", "travellers must be 1 to 9");
  const order = {
    id: id("O"), secret: randomBytes(18).toString("base64url"), productId: product.id, version: version.version,
    operatorId: operator.id, status: "pending_payment", start, travellers,
    amount: version.price.amount * travellers, currency: version.price.currency, createdAt: now, ticketId: null,
  };
  if (version.needs.includes("od")) order.od = { from: stop(input.od?.from, "od.from"), to: stop(input.od?.to, "od.to") };
  if (version.needs.includes("holder")) {
    const name = input.holder?.name;
    const born = input.holder?.birthYear;
    if (typeof name !== "string" || name.trim().length < 3 || name.length > 80 || !Number.isInteger(born) || born < 1900 || born > new Date(now).getUTCFullYear()) {
      throw new ApiError(400, "invalid", "a personal ticket needs holder.name and holder.birthYear");
    }
    order.holder = { name: name.trim(), birthYear: born };
  }
  if (input.deviceKey !== undefined && input.deviceKey !== null) {
    if (typeof input.deviceKey !== "string" || !/^[A-Za-z0-9_-]{86}$/.test(input.deviceKey)) throw new ApiError(400, "invalid", "deviceKey must be 64 bytes, base64url");
    order.deviceKey = input.deviceKey;
  }
  store.data.orders[order.id] = order;
  store.save();
  return order;
}

/**
 * Step 2: the payment went through, the ticket is issued. Calling it again returns the same ticket.
 * In this prototype the payment is a demo step; the real one is Stripe with a split payout to the operator
 * (already built in services/ticket-shop).
 */
export async function issueTicket(store, order, now = Date.now()) {
  if (order.status === "paid") return store.data.tickets[order.ticketId];
  if (order.status !== "pending_payment") throw new ApiError(409, "order_closed", "this order cannot be paid any more");
  const product = store.data.products[order.productId];
  const version = product.versions.find((v) => v.version === order.version);
  const operator = store.data.operators[order.operatorId];
  const key = operator.keys.find((k) => k.status === "active" && k.privateJwk);
  if (!key || operator.status !== "active") throw new ApiError(409, "operator_inactive", "this operator is not selling at the moment");
  const window = resolveWindow(version.validity.time, Math.max(order.start, now - 300000), version.validity.timeZone);
  const payload = {
    v: 1, id: id("T"), iss: operator.id, kid: key.kid, p: product.id, pv: version.version, vh: version.hash,
    nbf: Math.floor(window.from / 1000), exp: Math.floor(window.until / 1000), iat: Math.floor(now / 1000),
    n: order.travellers, cls: version.validity.class,
  };
  if (order.od) payload.od = order.od;
  if (order.holder) { payload.hn = order.holder.name; payload.hb = order.holder.birthYear; }
  if (order.deviceKey) payload.dk = order.deviceKey;
  const commission = Math.round((order.amount * operator.commissionBps) / 10000);
  const ticket = {
    id: payload.id, orderId: order.id, operatorId: operator.id, productId: product.id, version: version.version,
    token: await signTicket(payload, key.privateJwk), validFrom: window.from, validUntil: window.until,
    amount: order.amount, currency: order.currency, commission, issuedAt: now, status: "valid", od: order.od ?? null,
    live: Boolean(order.deviceKey),
  };
  store.data.tickets[ticket.id] = ticket;
  order.status = "paid";
  order.ticketId = ticket.id;
  delete order.holder; // the name lives in the ticket the buyer holds, not in our database
  store.save();
  return ticket;
}

/** Refund or cancellation: the ticket goes on the list every checking device loads. */
export function revokeTicket(store, operator, ticketId, reason = "refund", now = Date.now()) {
  const ticket = store.data.tickets[ticketId];
  if (!ticket || ticket.operatorId !== operator.id) throw new ApiError(404, "not_found", "no such ticket");
  ticket.status = "revoked";
  store.data.revoked[ticketId] = { at: now, reason: String(reason).slice(0, 40) };
  store.save();
  return ticket;
}

/**
 * Checking devices report what they saw when they are back online. A single-ride ticket seen on two different
 * vehicles, or a ticket seen by many devices at once, shows up here.
 */
export function recordInspections(store, operator, events, now = Date.now()) {
  if (!Array.isArray(events) || events.length > 500) throw new ApiError(400, "invalid", "events must be a list of at most 500");
  const out = [];
  for (const event of events) {
    if (typeof event?.ticketId !== "string") continue;
    const earlier = store.data.inspections.filter((i) => i.ticketId === event.ticketId);
    const entry = {
      ticketId: event.ticketId.slice(0, 20), by: operator.id, at: Number.isFinite(event.at) ? event.at : now,
      result: String(event.result ?? "valid").slice(0, 20), line: typeof event.line === "string" ? event.line.slice(0, 40) : null,
      device: typeof event.device === "string" ? event.device.slice(0, 40) : null,
    };
    store.data.inspections.push(entry);
    out.push({ ticketId: entry.ticketId, seenBefore: earlier.length, otherDevices: new Set(earlier.map((i) => i.device).filter((d) => d !== entry.device)).size });
  }
  if (store.data.inspections.length > 50000) store.data.inspections.splice(0, store.data.inspections.length - 50000);
  store.save();
  return out;
}

/** What the operator is owed: sales minus Publit's commission, refunds taken out. */
export function statement(store, operator, { from = 0, until = Infinity } = {}) {
  const lines = {};
  const total = { tickets: 0, refunded: 0, gross: 0, commission: 0, net: 0, currency: null };
  for (const ticket of Object.values(store.data.tickets)) {
    if (ticket.operatorId !== operator.id || ticket.issuedAt < from || ticket.issuedAt > until) continue;
    const line = lines[ticket.productId] ??= { productId: ticket.productId, tickets: 0, refunded: 0, gross: 0, commission: 0, net: 0 };
    total.currency ??= ticket.currency;
    if (ticket.status === "revoked") { line.refunded += 1; total.refunded += 1; continue; }
    for (const target of [line, total]) {
      target.tickets += 1;
      target.gross += ticket.amount;
      target.commission += ticket.commission;
      target.net += ticket.amount - ticket.commission;
    }
  }
  return { operatorId: operator.id, commissionBps: operator.commissionBps, total, products: Object.values(lines) };
}

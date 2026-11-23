// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Every ticket seller Publit can buy from. A provider is switched on by its credentials (see README);
// without them it is skipped and the app keeps showing the operator's own ticket link for that leg.
//
// A provider is an object with:
//   id, name
//   enabled(env)                              → credentials present
//   covers(leg)                               → could sell this leg at all (mode, country …), no network
//   offers(leg, request, env)                 → [{ title, operator, amount (minor units), currency, refundable, data }]
//   reserve(data, customer, env)              → { ref, amount, currency, expiresAt }   (holds seats/price, no payment)
//   confirm(ref, customer, env)               → booking  (after the payment is authorised; must be safe to repeat)
//   tickets(booking, env, fetch, customer)    → [{ title?, operator?, origin?, destination?, validFrom?, validUntil?,
//                                                  passenger?, reference?, barcode?: { format, message }, pdf?: base64 }]
//   cancel(ref, env)                          → releases a reservation that was not paid
//
// To add a seller (a transport authority's ticket API, OSDM for a railway, …) write such an object and list it
// below. Order matters: the first provider with an offer for a leg wins.

import { distribusion } from "./distribusion.js";
import { demo } from "./demo.js";

export const providers = [distribusion, demo];

export function provider(id) {
  return providers.find((p) => p.id === id) ?? null;
}

export function active(env, list = providers) {
  return list.filter((p) => p.enabled(env));
}

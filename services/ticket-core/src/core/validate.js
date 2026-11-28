// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// The conductor's check. Needs no network: everything it trusts comes from the trust list, which the device
// loads when it is online and which is signed by the root key built into the checking app.
//
// Trust list (JSON, signed as one string):
//   { version, issuedAt, validUntil,
//     issuers:  [{ id, name, country, status, keys: [{ kid, jwk, from, until, status }] }],
//     operators: [{ id, name, aliases }]            directory, to recognise whose vehicle this is
//     products: { "<id>@<version>": { operatorId, name, validity, hash } }
//     revoked:  [ticket ids] }
//
// The same idea as the EU Digital COVID Certificate: many issuers, one list of their keys, offline checks.

import { parseTicket, verifyTicketSignature, verifyProof, verifyText } from "./token.js";
import { coverLeg, sameStop } from "./coverage.js";
import { fingerprint } from "./bytes.js";

/** Verifies the root signature and returns the list, or null. */
export async function openTrustList(signed, rootJwk) {
  if (!signed || typeof signed.list !== "string" || typeof signed.signature !== "string") return null;
  if (!(await verifyText(signed.list, signed.signature, rootJwk))) return null;
  try {
    return JSON.parse(signed.list);
  } catch {
    return null;
  }
}

const MAX_PROOF_AGE = 60; // seconds a live code stays good
const CLOCK_SKEW = 30;

/**
 * → { level: "valid" | "check" | "invalid", code, checks: [{ name, ok, code }], ticket, product, scope }
 * `context` (optional) says where the conductor stands: { operatorId | agencyName, mode, line, stop }.
 */
export async function checkTicket(text, trust, { now = Date.now(), context = null } = {}) {
  const checks = [];
  const fail = (code, extra = {}) => ({ level: "invalid", code, checks, ...extra });
  const parsed = parseTicket(text);
  if (!parsed) return fail("not_a_ticket");
  const ticket = parsed.payload;
  const seconds = Math.floor(now / 1000);

  const issuer = trust.issuers.find((i) => i.id === ticket.iss);
  const key = issuer?.keys.find((k) => k.kid === ticket.kid);
  if (!issuer || !key) { checks.push({ name: "issuer", ok: false, code: "unknown_issuer" }); return fail("unknown_issuer", { ticket }); }
  if (issuer.status !== "active") { checks.push({ name: "issuer", ok: false, code: "issuer_suspended" }); return fail("issuer_suspended", { ticket }); }
  // A key is judged at the moment the ticket was issued, so tickets survive a routine key change.
  const issued = ticket.iat ?? ticket.nbf;
  const keyOk = key.status !== "compromised" && issued >= key.from && (key.until === null || issued <= key.until);
  checks.push({ name: "issuer", ok: keyOk, code: keyOk ? "known_issuer" : "key_not_valid", detail: issuer.name });
  if (!keyOk) return fail("key_not_valid", { ticket });

  const signed = await verifyTicketSignature(parsed, key.jwk);
  checks.push({ name: "signature", ok: signed, code: signed ? "signature_ok" : "signature_bad" });
  if (!signed) return fail("signature_bad", { ticket });

  const product = trust.products[`${ticket.p}@${ticket.pv}`];
  const productOk = Boolean(product) && product.operatorId === ticket.iss && product.hash === ticket.vh
    && (await fingerprint(product.validity)) === ticket.vh;
  checks.push({ name: "product", ok: productOk, code: productOk ? "product_ok" : "product_unknown" });
  if (!productOk) return fail("product_unknown", { ticket });

  const revoked = trust.revoked.includes(ticket.id);
  checks.push({ name: "revocation", ok: !revoked, code: revoked ? "revoked" : "not_revoked" });
  if (revoked) return fail("revoked", { ticket, product });

  if (ticket.dk) {
    let ok = Boolean(parsed.proof) && (await verifyProof(parsed));
    let code = ok ? "live_ok" : parsed.proof ? "live_bad" : "live_missing";
    if (ok && Math.abs(seconds - parsed.proof.at) > MAX_PROOF_AGE + CLOCK_SKEW) { ok = false; code = "live_stale"; }
    checks.push({ name: "live", ok, code });
    if (!ok) return fail(code, { ticket, product });
  }

  const timeCode = seconds + CLOCK_SKEW < ticket.nbf ? "not_yet_valid" : seconds - CLOCK_SKEW > ticket.exp ? "expired" : "in_time";
  checks.push({ name: "time", ok: timeCode === "in_time", code: timeCode });
  if (timeCode !== "in_time") return fail(timeCode, { ticket, product });

  const entitlement = { validFrom: ticket.nbf * 1000, validUntil: ticket.exp * 1000, validity: product.validity, od: ticket.od ?? null };
  let level = "valid";
  let code = "valid";
  let scope = null;
  if (context) {
    const route = (product.validity.area ?? []).find((r) => r.type === "route");
    const ends = route ? [route.from ?? ticket.od?.from, route.to ?? ticket.od?.to] : [];
    const atEnd = ends.some((s) => s && context.stop && sameStop(context.stop, s));
    const leg = {
      mode: context.mode, operatorId: context.operatorId, agencyName: context.agencyName, routeShortName: context.line,
      from: context.stop ?? {}, to: context.stop ?? {}, startTime: new Date(now).toISOString(),
    };
    scope = coverLeg(leg, entitlement, { operators: trust.operators }, Boolean(route));
    if (scope.covered === true && route && !atEnd) scope = { ...scope, covered: null, reason: "route_between" };
    checks.push({ name: "scope", ok: scope.covered === true, code: scope.reason });
    if (scope.covered === false) { level = "invalid"; code = `scope_${scope.reason}`; }
    else if (scope.covered === null) { level = "check"; code = `scope_${scope.reason}`; }
  }
  if (level === "valid" && product.validity.personal) { level = "check"; code = "check_id"; }
  return { level, code, checks, ticket, product, entitlement, scope };
}

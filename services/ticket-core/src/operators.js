// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Operators and how they come on board.
//
// Every operator Publit knows from the timetables is in the directory from day one ("listed"): that is enough
// to recognise whose vehicle a ride is on. Joining the sale goes in levels, so nobody has to change systems:
//
//   link      Publit links to the operator's own shop. No contract, no ticket from us.
//   hosted    The operator has no sales system. It enters its tickets here, Publit issues and signs them with
//             a key kept for that operator, conductors check with the web check (or by eye).
//   own-keys  The operator issues tickets itself and only registers its public key, so its tickets pass the
//             same check everywhere.
//   api       The operator has a sales system (OSDM, Distribusion, its own API). Publit sells through an
//             adapter and hands over the operator's original ticket.
//
// States: listed → pending (applied) → active (checked by Publit) → suspended.

import { randomBytes, createHash, timingSafeEqual } from "node:crypto";
import { plain } from "./core/bytes.js";
import { generateKeyPair, isPublicJwk } from "./core/token.js";

export const LEVELS = ["link", "hosted", "own-keys", "api"];

export class ApiError extends Error {
  constructor(status, code, message) {
    super(message ?? code);
    this.status = status;
    this.code = code;
  }
}

export function slug(text) {
  return plain(text).replaceAll(" ", "-").slice(0, 48);
}

export function hashKey(key) {
  return createHash("sha256").update(key).digest("hex");
}

export function sameHash(a, b) {
  const x = Buffer.from(a, "hex");
  const y = Buffer.from(b, "hex");
  return x.length === y.length && timingSafeEqual(x, y);
}

function text(value, max, field, required = true) {
  if (value === undefined || value === null || value === "") {
    if (required) throw new ApiError(400, "invalid", `${field} is missing`);
    return null;
  }
  if (typeof value !== "string" || value.length > max) throw new ApiError(400, "invalid", `${field} is not valid`);
  return value.trim();
}

/** What anyone may see of an operator. */
export function publicOperator(operator) {
  return {
    id: operator.id, name: operator.name, country: operator.country, status: operator.status, level: operator.level,
    modes: operator.modes, aliases: operator.aliases, demo: operator.demo ?? false, format: operator.format?.type ?? "publit",
    keys: operator.keys.map((k) => ({ kid: k.kid, from: k.from, until: k.until, status: k.status, hosted: Boolean(k.privateJwk) })),
  };
}

/** Adds an operator to the directory without any contract (from timetable data). */
export function listOperator(store, { id, name, country, aliases = [], modes = [], demo = false }) {
  const key = id ?? slug(name);
  store.data.operators[key] ??= {
    id: key, name, legalName: null, country, aliases, modes, status: "listed", level: "link", contact: null,
    company: null, commissionBps: 0, keys: [], apiKeyHash: null, demo, createdAt: Date.now(),
  };
  return store.data.operators[key];
}

/**
 * An operator applies. Returns the operator and its API key; the key is shown once and only its hash is kept.
 * An entry that is merely "listed" may be claimed; anything else with the same name is refused.
 */
export function applyOperator(store, input, now = Date.now()) {
  const name = text(input.name, 120, "name");
  const id = slug(name);
  if (!id) throw new ApiError(400, "invalid", "name is not valid");
  const level = input.level ?? "hosted";
  if (!LEVELS.includes(level)) throw new ApiError(400, "invalid", `level must be one of ${LEVELS.join(", ")}`);
  const country = text(input.country, 2, "country").toUpperCase();
  if (!/^[A-Z]{2}$/.test(country)) throw new ApiError(400, "invalid", "country must be a two-letter code");
  const email = text(input.contactEmail, 200, "contactEmail");
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new ApiError(400, "invalid", "contactEmail is not valid");
  if (level === "own-keys" && !isPublicJwk(input.publicKeyJwk)) {
    throw new ApiError(400, "invalid", "publicKeyJwk must be a public P-256 key (JWK) for level own-keys");
  }
  const existing = store.data.operators[id];
  if (existing && existing.status !== "listed") throw new ApiError(409, "exists", "an operator with this name has already applied");
  const apiKey = `ptc_${randomBytes(24).toString("base64url")}`;
  const commission = Number.isInteger(input.commissionBps) ? input.commissionBps : 500;
  if (commission < 0 || commission > 3000) throw new ApiError(400, "invalid", "commissionBps must be between 0 and 3000");
  const operator = {
    ...(existing ?? {}),
    id, name, legalName: text(input.legalName, 200, "legalName", false), country, level, status: "pending",
    aliases: [...new Set([...(existing?.aliases ?? []), ...(Array.isArray(input.aliases) ? input.aliases.filter((a) => typeof a === "string").slice(0, 20) : [])])],
    modes: Array.isArray(input.modes) ? input.modes.filter((m) => typeof m === "string").slice(0, 20) : existing?.modes ?? [],
    contact: { email },
    company: { registerNo: text(input.registerNo, 60, "registerNo", false), vatId: text(input.vatId, 30, "vatId", false) },
    commissionBps: commission,
    keys: level === "own-keys" ? [{ kid: `${id}-1`, jwk: input.publicKeyJwk, from: Math.floor(now / 1000), until: null, status: "active" }] : [],
    apiKeyHash: hashKey(apiKey), demo: Boolean(input.demo), createdAt: existing?.createdAt ?? now, appliedAt: now,
  };
  store.data.operators[id] = operator;
  store.save();
  return { operator, apiKey };
}

/** Publit has checked the company: the operator goes live. Hosted operators get their signing key now. */
export async function approveOperator(store, id, now = Date.now()) {
  const operator = store.data.operators[id];
  if (!operator) throw new ApiError(404, "not_found", "no such operator");
  if (operator.status === "listed") throw new ApiError(409, "not_applied", "this operator has not applied yet");
  if (operator.level === "hosted" && !operator.keys.some((k) => k.status === "active")) await addHostedKey(operator, now);
  operator.status = "active";
  operator.approvedAt = now;
  store.save();
  return operator;
}

export async function addHostedKey(operator, now) {
  const pair = await generateKeyPair();
  operator.keys.push({
    kid: `${operator.id}-${operator.keys.length + 1}`, jwk: pair.publicJwk, privateJwk: pair.privateJwk,
    from: Math.floor(now / 1000), until: null, status: "active",
  });
}

/**
 * Key change. The old key stops signing but stays in the trust list, so tickets already sold keep working.
 * `compromised: true` instead marks it as stolen: every ticket signed with it is refused from now on.
 */
export async function rotateKey(store, operator, { publicKeyJwk = null, compromised = false } = {}, now = Date.now()) {
  const seconds = Math.floor(now / 1000);
  for (const key of operator.keys) {
    if (key.status !== "active") continue;
    key.status = compromised ? "compromised" : "retired";
    key.until = seconds;
    delete key.privateJwk;
  }
  if (operator.level === "own-keys") {
    if (!isPublicJwk(publicKeyJwk)) throw new ApiError(400, "invalid", "publicKeyJwk must be a public P-256 key (JWK)");
    operator.keys.push({ kid: `${operator.id}-${operator.keys.length + 1}`, jwk: publicKeyJwk, from: seconds, until: null, status: "active" });
  } else {
    await addHostedKey(operator, now);
  }
  store.save();
  return operator;
}

export function setStatus(store, id, status) {
  const operator = store.data.operators[id];
  if (!operator) throw new ApiError(404, "not_found", "no such operator");
  operator.status = status;
  store.save();
  return operator;
}

/** The operator a request's API key belongs to, or null. */
export function operatorForKey(store, apiKey) {
  if (typeof apiKey !== "string" || !apiKey.startsWith("ptc_")) return null;
  const hash = hashKey(apiKey);
  return Object.values(store.data.operators).find((o) => o.apiKeyHash && sameHash(o.apiKeyHash, hash)) ?? null;
}

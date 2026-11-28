// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// The signed ticket that goes into the QR code.
//
//   PT1.<payload>.<signature>                         static ticket
//   PT1.<payload>.<signature>~<seconds>.<proof>       live ticket shown by the buyer's device
//
// payload   = base64url(JSON), see `orders.js` for the fields
// signature = ECDSA P-256 / SHA-256 by the issuer's key (64 bytes r||s), over "PT1.<payload>"
// proof     = ECDSA by the device key named in the payload (`dk`), over everything before the last dot.
//             It changes every few seconds, so a screenshot stops working (the idea of UIC's dynamic barcode).
//
// ECDSA P-256 is what UIC rail barcodes and Sweden's BoB tickets use, and every browser and phone can verify
// it without a library. This is the prototype's own envelope; for rail the production path is a real UIC
// barcode with the same content (see README).

import { b64u, unb64u, encoder, decoder } from "./bytes.js";

const CURVE = { name: "ECDSA", namedCurve: "P-256" };
const SIGN = { name: "ECDSA", hash: "SHA-256" };
export const PREFIX = "PT1";

export async function generateKeyPair() {
  const pair = await crypto.subtle.generateKey(CURVE, true, ["sign", "verify"]);
  const publicJwk = await crypto.subtle.exportKey("jwk", pair.publicKey);
  const privateJwk = await crypto.subtle.exportKey("jwk", pair.privateKey);
  return { publicJwk: slim(publicJwk), privateJwk: { ...slim(privateJwk), d: privateJwk.d } };
}

function slim(jwk) {
  return { kty: jwk.kty, crv: jwk.crv, x: jwk.x, y: jwk.y };
}

/** A public JWK is accepted only when it is a P-256 point and carries no private part. */
export function isPublicJwk(jwk) {
  return Boolean(jwk) && jwk.kty === "EC" && jwk.crv === "P-256" && typeof jwk.x === "string"
    && typeof jwk.y === "string" && jwk.d === undefined;
}

async function privateKey(jwk) {
  return crypto.subtle.importKey("jwk", jwk, CURVE, false, ["sign"]);
}

async function publicKey(jwk) {
  return crypto.subtle.importKey("jwk", slim(jwk), CURVE, false, ["verify"]);
}

export async function signText(text, privateJwk) {
  return b64u(new Uint8Array(await crypto.subtle.sign(SIGN, await privateKey(privateJwk), encoder.encode(text))));
}

export async function verifyText(text, signature, publicJwk) {
  try {
    return await crypto.subtle.verify(SIGN, await publicKey(publicJwk), unb64u(signature), encoder.encode(text));
  } catch {
    return false;
  }
}

/** The device key travels inside the ticket as the raw point (x||y), 64 bytes. */
export function deviceKeyFromJwk(jwk) {
  const raw = new Uint8Array(64);
  raw.set(unb64u(jwk.x), 0);
  raw.set(unb64u(jwk.y), 32);
  return b64u(raw);
}

export function deviceKeyToJwk(text) {
  const raw = unb64u(text);
  if (raw.length !== 64) throw new Error("device key must be 64 bytes");
  return { kty: "EC", crv: "P-256", x: b64u(raw.slice(0, 32)), y: b64u(raw.slice(32)) };
}

export async function signTicket(payload, privateJwk) {
  const head = `${PREFIX}.${b64u(encoder.encode(JSON.stringify(payload)))}`;
  return `${head}.${await signText(head, privateJwk)}`;
}

/** Splits what a scanner read. Returns null when it is not one of our tickets. Verifies nothing. */
export function parseTicket(text) {
  if (typeof text !== "string" || text.length > 4096 || !text.startsWith(`${PREFIX}.`)) return null;
  const [token, live, extra] = text.trim().split("~");
  if (extra !== undefined) return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  let payload;
  try {
    payload = JSON.parse(decoder.decode(unb64u(parts[1])));
  } catch {
    return null;
  }
  if (!payload || typeof payload !== "object" || typeof payload.id !== "string") return null;
  const parsed = { token, head: `${parts[0]}.${parts[1]}`, signature: parts[2], payload, proof: null };
  if (live !== undefined) {
    const [seconds, signature, more] = live.split(".");
    if (!/^\d{9,11}$/.test(seconds ?? "") || !signature || more !== undefined) return null;
    parsed.proof = { at: Number(seconds), signature, signed: `${token}~${seconds}` };
  }
  return parsed;
}

export function verifyTicketSignature(parsed, publicJwk) {
  return verifyText(parsed.head, parsed.signature, publicJwk);
}

/** What the buyer's device shows: the ticket plus a fresh proof made with the device's own key. */
export async function present(token, devicePrivateJwk, nowSeconds = Math.floor(Date.now() / 1000)) {
  const signed = `${token}~${nowSeconds}`;
  return `${signed}.${await signText(signed, devicePrivateJwk)}`;
}

export async function verifyProof(parsed) {
  if (!parsed.proof || typeof parsed.payload.dk !== "string") return false;
  try {
    return await verifyText(parsed.proof.signed, parsed.proof.signature, deviceKeyToJwk(parsed.payload.dk));
  } catch {
    return false;
  }
}

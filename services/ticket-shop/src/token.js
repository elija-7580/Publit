// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Signed offer tokens. An offer goes to the app and comes back at checkout; the signature makes sure
// the app cannot change the provider, the trip or the price in between. Nothing is stored on the server.

const encoder = new TextEncoder();

function base64url(bytes) {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function fromBase64url(text) {
  const padded = text.replaceAll("-", "+").replaceAll("_", "/") + "===".slice((text.length + 3) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

async function key(secret) {
  if (typeof secret !== "string" || secret.length < 32) throw new Error("TOKEN_SECRET must have at least 32 characters");
  return crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

/** Signs `payload` (JSON) and adds an expiry. */
export async function sign(payload, secret, ttlSeconds = 1800, now = Date.now()) {
  const body = base64url(encoder.encode(JSON.stringify({ ...payload, exp: Math.floor(now / 1000) + ttlSeconds })));
  const mac = await crypto.subtle.sign("HMAC", await key(secret), encoder.encode(body));
  return `${body}.${base64url(new Uint8Array(mac))}`;
}

/** The payload of a valid, unexpired token, else null. */
export async function verify(token, secret, now = Date.now()) {
  if (typeof token !== "string" || token.length > 8192) return null;
  const [body, mac, extra] = token.split(".");
  if (!body || !mac || extra !== undefined) return null;
  let ok = false;
  try {
    ok = await crypto.subtle.verify("HMAC", await key(secret), fromBase64url(mac), encoder.encode(body));
  } catch {
    return null;
  }
  if (!ok) return null;
  try {
    const payload = JSON.parse(new TextDecoder().decode(fromBase64url(body)));
    if (typeof payload.exp !== "number" || payload.exp * 1000 < now) return null;
    return payload;
  } catch {
    return null;
  }
}

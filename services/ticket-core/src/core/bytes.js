// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Small helpers shared by the server and the browser (the conductor's check runs the same code offline).

export const encoder = new TextEncoder();
export const decoder = new TextDecoder();

export function b64u(bytes) {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export function unb64u(text) {
  const padded = text.replaceAll("-", "+").replaceAll("_", "/") + "===".slice((text.length + 3) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

/** JSON with sorted keys, so the same value always gives the same bytes (and the same hash). */
export function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).filter((k) => value[k] !== undefined).sort()
      .map((k) => `${JSON.stringify(k)}:${canonical(value[k])}`).join(",")}}`;
  }
  return JSON.stringify(value ?? null);
}

export async function sha256(bytes) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
}

/** Short fingerprint of a value: first 12 bytes of the SHA-256 of its canonical JSON. */
export async function fingerprint(value) {
  return b64u((await sha256(encoder.encode(canonical(value)))).slice(0, 12));
}

/** Lower case, no accents, words separated by single spaces. Used to compare operator and stop names. */
export function plain(text) {
  return String(text ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").replaceAll("ß", "ss").toLowerCase()
    .replace(/[^a-z0-9]+/g, " ").trim();
}

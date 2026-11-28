// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Secrets an operator hands over (a shared secret, a token for its sales system, a signing key) are kept
// encrypted (AES-256-GCM). The key comes from the environment (SECRETS_KEY) and is never written to the store,
// so a copy of the data file alone opens nothing. The API never returns a secret, only whether one is set.

import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";

/** The 32-byte key for a SECRETS_KEY setting, or null when none is set. */
export function vaultKey(setting) {
  if (typeof setting !== "string" || setting.length < 24) return null;
  return createHash("sha256").update(`publit-ticket-core:${setting}`).digest();
}

export function seal(text, key) {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const body = Buffer.concat([cipher.update(String(text), "utf8"), cipher.final()]);
  return `v1.${iv.toString("base64url")}.${cipher.getAuthTag().toString("base64url")}.${body.toString("base64url")}`;
}

/** The secret, or null when it cannot be opened with this key (wrong key, changed data). */
export function unseal(sealed, key) {
  const parts = typeof sealed === "string" ? sealed.split(".") : [];
  if (parts.length !== 4 || parts[0] !== "v1" || !key) return null;
  try {
    const decipher = createDecipheriv("aes-256-gcm", key, Buffer.from(parts[1], "base64url"));
    decipher.setAuthTag(Buffer.from(parts[2], "base64url"));
    return Buffer.concat([decipher.update(Buffer.from(parts[3], "base64url")), decipher.final()]).toString("utf8");
  } catch {
    return null;
  }
}

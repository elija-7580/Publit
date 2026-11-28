// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// The code a conductor's device reads. Every operator already has checking software, and it only accepts
// codes in its own format. So each operator gets a format here, and a ticket sold through Publit carries the
// code that operator's devices expect:
//
//   publit         Publit's own signed code (PT1). For operators without a system; checked with the web check.
//   operator-api   The operator's sales system issues the code (its API is called when the ticket is paid) and
//                  Publit hands it over unchanged. Its devices check it like any ticket sold by the operator.
//   shared-secret  The operator's devices check a keyed checksum (HMAC). The operator gives Publit the secret
//                  and the layout of the text; Publit builds the same code.
//   uic-918-3      The Aztec code of European rail tickets, signed with a key whose public half the operator
//                  puts into its key list (or with a key the operator hands over).
//
// Only Publit (the admin token) sets a format. Secrets go into the vault (src/vault.js) and never come back
// out through the API. Whatever the format, Publit also keeps its own signed record of the ticket, so it can
// state for any code whether it issued it and whether it is still good (POST /v1/admin/verify).

import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { ApiError, addHostedKey } from "./operators.js";
import { seal, unseal } from "./vault.js";
import { decodeUic918, encodeUic918, newUicKey, uicPublicKey } from "./formats/uic918.js";

const SYMBOLOGIES = ["qr", "aztec", "datamatrix", "pdf417", "code128"];
const DEFAULT_TEMPLATE = "{id}|{product}|{from}|{until}|{n}";

export const FORMATS = [
  { type: "publit", name: { de: "Publit-Code (PT1)", en: "Publit code (PT1)" }, secret: "none",
    about: { de: "Publits eigener signierter Code. Für Unternehmen ohne Prüfsystem: Kontrolle mit der Web-Prüfung.", en: "Publit's own signed code. For operators without a checking system: checked with the web check." },
    fields: [] },
  { type: "operator-api", name: { de: "Code vom System des Unternehmens", en: "Code from the operator's system" }, secret: "required",
    about: { de: "Beim Kauf ruft Publit das Vertriebssystem des Unternehmens auf und reicht dessen Originalcode weiter. Die Prüfgeräte lesen ihn wie jedes eigene Ticket.", en: "On purchase Publit calls the operator's sales system and passes on its original code. The checking devices read it like any ticket of their own." },
    fields: [{ id: "endpoint", label: { de: "Adresse der Schnittstelle (https)", en: "API address (https)" }, example: "https://vertrieb.beispiel.at/tickets" },
      { id: "symbology", label: { de: "Barcode-Art", en: "Barcode type" }, options: SYMBOLOGIES }],
    secretLabel: { de: "Zugangsschlüssel für die Schnittstelle", en: "Access token for the API" } },
  { type: "shared-secret", name: { de: "Prüfsumme mit gemeinsamem Geheimnis (HMAC)", en: "Checksum with a shared secret (HMAC)" }, secret: "required",
    about: { de: "Das Unternehmen gibt Publit sein Geheimnis und den Aufbau des Codes. Publit erzeugt denselben Code, den die Geräte des Unternehmens erwarten.", en: "The operator gives Publit its secret and the layout of the code. Publit produces the same code the operator's devices expect." },
    fields: [{ id: "template", label: { de: "Aufbau des Codes", en: "Layout of the code" }, example: DEFAULT_TEMPLATE },
      { id: "algorithm", label: { de: "Verfahren", en: "Algorithm" }, options: ["sha256", "sha512", "sha1"] },
      { id: "encoding", label: { de: "Schreibweise der Prüfsumme", en: "Checksum encoding" }, options: ["hex", "base64url"] },
      { id: "length", label: { de: "Länge der Prüfsumme (Zeichen, leer = ganz)", en: "Checksum length (characters, empty = all)" }, example: "16" },
      { id: "symbology", label: { de: "Barcode-Art", en: "Barcode type" }, options: SYMBOLOGIES }],
    secretLabel: { de: "Geheimnis des Unternehmens", en: "The operator's secret" } },
  { type: "uic-918-3", name: { de: "UIC 918.3 (Aztec-Code der Bahnen)", en: "UIC 918.3 (the railways' Aztec code)" }, secret: "optional",
    about: { de: "Der Barcode europäischer Bahntickets. Publit signiert; das Unternehmen trägt Publits öffentlichen Schlüssel in seine Schlüsselliste ein. Wird ein eigener Signierschlüssel übergeben, signiert Publit damit.", en: "The barcode of European rail tickets. Publit signs; the operator adds Publit's public key to its key list. If the operator hands over a signing key, Publit signs with that." },
    fields: [{ id: "rics", label: { de: "Unternehmenscode (RICS, 4 Ziffern)", en: "Company code (RICS, 4 digits)" }, example: "9999" },
      { id: "keyId", label: { de: "Schlüsselnummer (bis 5 Ziffern)", en: "Key number (up to 5 digits)" }, example: "1" }],
    secretLabel: { de: "Signierschlüssel (DSA, PEM). Leer lassen: Publit erzeugt einen", en: "Signing key (DSA, PEM). Leave empty: Publit creates one" } },
];

const hashCode = (code) => createHash("sha256").update(code).digest("hex");
export { hashCode };

/** What Publit may show of an operator's format: never the secret. */
export function formatView(operator) {
  const format = operator.format;
  if (!format) return { type: "publit", config: {}, hasSecret: false, setAt: null };
  return { type: format.type, config: format.config, hasSecret: Boolean(format.secret), setAt: format.setAt };
}

function need(key) {
  if (!key) throw new ApiError(503, "no_secrets_key", "SECRETS_KEY is not set, so secrets cannot be stored");
  return key;
}

function option(value, list, fallback, field) {
  if (value === undefined || value === null || value === "") return fallback;
  if (!list.includes(value)) throw new ApiError(400, "invalid", `${field} must be one of ${list.join(", ")}`);
  return value;
}

/** Publit sets how an operator's tickets are coded. A secret that is not sent again is kept. */
export async function setFormat(store, operator, input, { key, now = Date.now() } = {}) {
  const type = input.type;
  const spec = FORMATS.find((f) => f.type === type);
  if (!spec) throw new ApiError(400, "invalid", `type must be one of ${FORMATS.map((f) => f.type).join(", ")}`);
  if (operator.status === "listed") throw new ApiError(409, "not_applied", "this operator has not joined yet");
  const given = input.config && typeof input.config === "object" ? input.config : {};
  const secret = typeof input.secret === "string" && input.secret.trim() ? input.secret.trim() : null;
  if (secret && secret.length > 8000) throw new ApiError(400, "invalid", "secret is too long");
  const kept = operator.format?.type === type ? operator.format.secret ?? null : null;
  let config = {};
  let sealed = null;

  if (type === "operator-api") {
    let url = null;
    try { url = new URL(given.endpoint); } catch { /* handled below */ }
    if (!url || url.protocol !== "https:" || url.username || url.password) throw new ApiError(400, "invalid", "endpoint must be an https address");
    if (!secret && !kept) throw new ApiError(400, "invalid", "secret (the access token for the operator's API) is missing");
    config = { endpoint: url.toString(), symbology: option(given.symbology, SYMBOLOGIES, "qr", "symbology") };
    sealed = secret ? seal(secret, need(key)) : kept;
  } else if (type === "shared-secret") {
    const template = given.template === undefined || given.template === "" ? DEFAULT_TEMPLATE : given.template;
    if (typeof template !== "string" || template.length > 300 || !template.includes("{id}")) throw new ApiError(400, "invalid", "template must contain {id}");
    if (!secret && !kept) throw new ApiError(400, "invalid", "secret is missing");
    if (secret && secret.length < 16) throw new ApiError(400, "invalid", "secret must have at least 16 characters");
    const length = given.length === undefined || given.length === null || given.length === "" ? null : Number(given.length);
    if (length !== null && (!Number.isInteger(length) || length < 8 || length > 128)) throw new ApiError(400, "invalid", "length must be between 8 and 128");
    config = { template, algorithm: option(given.algorithm, ["sha256", "sha512", "sha1"], "sha256", "algorithm"),
      encoding: option(given.encoding, ["hex", "base64url"], "hex", "encoding"), length, symbology: option(given.symbology, SYMBOLOGIES, "qr", "symbology") };
    sealed = secret ? seal(secret, need(key)) : kept;
  } else if (type === "uic-918-3") {
    if (!/^\d{4}$/.test(String(given.rics ?? ""))) throw new ApiError(400, "invalid", "rics must be four digits");
    if (!/^\d{1,5}$/.test(String(given.keyId ?? "1"))) throw new ApiError(400, "invalid", "keyId must be up to five digits");
    let publicKeyPem = operator.format?.type === type ? operator.format.config.publicKeyPem : null;
    sealed = kept;
    if (secret) {
      publicKeyPem = uicPublicKey(secret);
      if (!publicKeyPem) throw new ApiError(400, "invalid", "secret must be a DSA private key in PEM form");
      sealed = seal(secret, need(key));
    } else if (!sealed) {
      const pair = newUicKey();
      publicKeyPem = pair.publicPem;
      sealed = seal(pair.privatePem, need(key));
    }
    config = { rics: String(given.rics), keyId: String(given.keyId ?? "1").padStart(5, "0"), symbology: "aztec", publicKeyPem, ownKey: Boolean(secret) || (kept !== null && operator.format.config.ownKey) };
  }
  // Publit's own signed record of each ticket needs a key for this operator, whatever the visible code is.
  if (!operator.keys.some((k) => k.status === "active" && k.privateJwk)) await addHostedKey(operator, now);
  operator.format = type === "publit" ? null : { type, config, secret: sealed, setAt: now };
  store.save();
  return operator;
}

function fill(template, ticket) {
  const values = { id: ticket.id, product: ticket.productId, operator: ticket.operatorId, from: Math.floor(ticket.validFrom / 1000), until: Math.floor(ticket.validUntil / 1000),
    fromIso: new Date(ticket.validFrom).toISOString(), untilIso: new Date(ticket.validUntil).toISOString(), n: ticket.travellers, class: ticket.class ?? 2 };
  return template.replace(/\{(\w+)\}/g, (all, name) => (name in values ? String(values[name]) : all));
}

function checksum(config, secret, text) {
  const mac = createHmac(config.algorithm, secret).update(text).digest(config.encoding);
  return config.length ? mac.slice(0, config.length) : mac;
}

function secretOf(operator, key) {
  const secret = unseal(operator.format.secret, key);
  if (secret === null) throw new ApiError(409, "secret_unreadable", "the stored secret for this operator cannot be opened with the current SECRETS_KEY; set it again");
  return secret;
}

/**
 * The code for one ticket in the operator's format.
 * `ticket`: { id, productId, operatorId, name, validFrom, validUntil, travellers, class, od, holder, price, issuedAt, timeZone, test }
 * → { code, encoding: "text" | "base64", symbology, reference }, or null for Publit's own format.
 */
export async function issueCode(operator, ticket, { key, fetch: call = globalThis.fetch } = {}) {
  const format = operator.format;
  if (!format) return null;
  const { config } = format;
  if (format.type === "shared-secret") {
    const text = fill(config.template, ticket);
    return { code: `${text}|${checksum(config, secretOf(operator, key), text)}`, encoding: "text", symbology: config.symbology, reference: null };
  }
  if (format.type === "uic-918-3") {
    const bytes = encodeUic918(ticket, config, secretOf(operator, key));
    return { code: bytes.toString("base64"), encoding: "base64", symbology: "aztec", reference: null };
  }
  // operator-api: the operator's own system issues the code.
  let data = null;
  try {
    const response = await call(config.endpoint, {
      method: "POST", signal: AbortSignal.timeout(8000),
      headers: { "content-type": "application/json", authorization: `Bearer ${secretOf(operator, key)}` },
      body: JSON.stringify({ reference: ticket.id, productId: ticket.productId, validFrom: new Date(ticket.validFrom).toISOString(), validUntil: new Date(ticket.validUntil).toISOString(),
        travellers: ticket.travellers, class: ticket.class ?? 2, od: ticket.od ?? null, holder: ticket.holder ?? null, test: Boolean(ticket.test) }),
    });
    if (response.ok) data = await response.json();
  } catch (error) {
    if (error instanceof ApiError) throw error;
  }
  if (!data || typeof data.code !== "string" || !data.code || data.code.length > 6000) {
    throw new ApiError(502, "operator_system", "the operator's system did not issue a code; nothing was sold");
  }
  return { code: data.code, encoding: data.encoding === "base64" ? "base64" : "text", symbology: config.symbology,
    reference: typeof data.reference === "string" ? data.reference.slice(0, 80) : null };
}

/**
 * Does this code carry what the operator's format demands? → true, false, or null when only the operator's
 * own system can tell (operator-api).
 */
export function verifyCode(operator, record, key) {
  const format = operator.format;
  if (!format || format.type !== record.format) return null;
  if (format.type === "shared-secret") {
    const cut = record.code.lastIndexOf("|");
    const secret = unseal(format.secret, key);
    if (cut < 0 || secret === null) return secret === null ? null : false;
    const expected = Buffer.from(checksum(format.config, secret, record.code.slice(0, cut)));
    const got = Buffer.from(record.code.slice(cut + 1));
    return expected.length === got.length && timingSafeEqual(expected, got);
  }
  if (format.type === "uic-918-3") return decodeUic918(Buffer.from(record.code, "base64"), format.config.publicKeyPem)?.signed === true;
  return null;
}

// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// A ticket as a UIC 918.3 barcode ("#UT", the Aztec code on European rail tickets), so that checking devices
// built for that standard can read it. Written from the public description of the format:
//
//   "#UT" | version "01" | company code (RICS, 4 digits) | key id (5 digits) | DSA signature (DER, padded to
//   50 bytes) | length of what follows (4 digits) | zlib-compressed records
//
//   record:  id (6) | version (2) | length including these 12 bytes (4 digits) | data
//   U_HEAD:  company code (4) | ticket number (20) | issued DDMMYYYYHHMM (12) | flags (1) | languages (2 + 2)
//   U_TLAY:  "RCT2" | number of fields (4) | fields: line (2) column (2) height (2) width (2) format (1)
//            text length (4) text
//
// The signature (DSA with SHA-1, as version 01 defines it) covers the compressed records. A device accepts
// the code once the issuer's company code and public key are in its key list; that step is the operator's
// (or the UIC key registry's) and cannot be done from here.

import { createPrivateKey, createPublicKey, generateKeyPairSync, sign, verify } from "node:crypto";
import { deflateSync, inflateSync } from "node:zlib";

const digits = (value, length) => String(value).padStart(length, "0").slice(-length);
const two = (n) => digits(n, 2);

function record(id, version, data) {
  return Buffer.concat([Buffer.from(`${id}${version}${digits(data.length + 12, 4)}`, "latin1"), data]);
}

function field(line, column, width, text, format = 0) {
  const bytes = Buffer.from(String(text).slice(0, width), "utf8");
  return Buffer.concat([Buffer.from(`${two(line)}${two(column)}01${two(width)}${format}${digits(bytes.length, 4)}`, "latin1"), bytes]);
}

function stamp(ms, timeZone) {
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-GB", { timeZone, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
    .formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  return { compact: `${p.day}${p.month}${p.year}${p.hour}${p.minute}`, text: `${p.day}.${p.month}.${p.year} ${p.hour}:${p.minute}` };
}

/** A new DSA key pair as PEM (1024/160 bits, what version 01 of the barcode uses). */
export function newUicKey() {
  const pair = generateKeyPairSync("dsa", { modulusLength: 1024, divisorLength: 160 });
  return { privatePem: pair.privateKey.export({ type: "pkcs8", format: "pem" }), publicPem: pair.publicKey.export({ type: "spki", format: "pem" }) };
}

/** The public key (PEM) for a DSA private key (PEM), or null when it is not one. */
export function uicPublicKey(privatePem) {
  try {
    const key = createPrivateKey(privatePem);
    if (key.asymmetricKeyType !== "dsa") return null;
    return createPublicKey(key).export({ type: "spki", format: "pem" });
  } catch {
    return null;
  }
}

/** → Buffer with the whole barcode content. `ticket`: { id, name, validFrom, validUntil, travellers, class, od, holder, price, issuedAt, timeZone }. */
export function encodeUic918(ticket, { rics, keyId, language = "DE" }, privatePem) {
  const zone = ticket.timeZone ?? "Europe/Vienna";
  const head = Buffer.from(`${digits(rics, 4)}${String(ticket.id).padEnd(20, " ").slice(0, 20)}${stamp(ticket.issuedAt, zone).compact}0${language}EN`, "latin1");
  const fields = [
    field(0, 0, 50, ticket.name, 1),
    field(2, 0, 50, `${language === "DE" ? "Gültig ab" : "Valid from"} ${stamp(ticket.validFrom, zone).text}`),
    field(3, 0, 50, `${language === "DE" ? "Gültig bis" : "Valid until"} ${stamp(ticket.validUntil, zone).text}`),
  ];
  if (ticket.od) fields.push(field(5, 0, 34, ticket.od.from.name ?? ticket.od.from.id), field(5, 35, 34, ticket.od.to.name ?? ticket.od.to.id));
  fields.push(field(7, 0, 30, `${ticket.travellers} × · ${language === "DE" ? "Klasse" : "Class"} ${ticket.class ?? 2}`));
  if (ticket.holder) fields.push(field(8, 0, 50, `${ticket.holder.name}, ${ticket.holder.birthYear}`));
  if (ticket.price) fields.push(field(12, 52, 18, ticket.price));
  fields.push(field(14, 0, 30, ticket.id));
  const layout = Buffer.concat([Buffer.from(`RCT2${digits(fields.length, 4)}`, "latin1"), ...fields]);
  const packed = deflateSync(Buffer.concat([record("U_HEAD", "01", head), record("U_TLAY", "01", layout)]));
  if (packed.length > 9999) throw new Error("ticket too large for a UIC 918.3 barcode");
  const signature = Buffer.alloc(50);
  sign("sha1", packed, createPrivateKey(privatePem)).copy(signature);
  return Buffer.concat([Buffer.from(`#UT01${digits(rics, 4)}${digits(keyId, 5)}`, "latin1"), signature, Buffer.from(digits(packed.length, 4), "latin1"), packed]);
}

/** Reads a barcode back. → { rics, keyId, signed (true/false, or null without a key), ticketId, issued, fields } or null. */
export function decodeUic918(bytes, publicPem = null) {
  try {
    if (bytes.length < 80 || bytes.subarray(0, 5).toString("latin1") !== "#UT01") return null;
    const length = Number(bytes.subarray(64, 68).toString("latin1"));
    const packed = bytes.subarray(68);
    if (!Number.isInteger(length) || packed.length !== length) return null;
    const der = bytes.subarray(14, 64);
    const signed = publicPem ? der[0] === 0x30 && verify("sha1", packed, createPublicKey(publicPem), der.subarray(0, der[1] + 2)) : null;
    let rest = inflateSync(packed);
    const out = { rics: bytes.subarray(5, 9).toString("latin1"), keyId: bytes.subarray(9, 14).toString("latin1"), signed, ticketId: null, issued: null, fields: [] };
    while (rest.length >= 12) {
      const size = Number(rest.subarray(8, 12).toString("latin1"));
      if (!Number.isInteger(size) || size < 12 || size > rest.length) return null;
      const id = rest.subarray(0, 6).toString("latin1");
      const data = rest.subarray(12, size);
      if (id === "U_HEAD") { out.ticketId = data.subarray(4, 24).toString("latin1").trim(); out.issued = data.subarray(24, 36).toString("latin1"); }
      if (id === "U_TLAY") {
        let at = 8;
        while (at + 13 <= data.length) {
          const textLength = Number(data.subarray(at + 9, at + 13).toString("latin1"));
          out.fields.push({ line: Number(data.subarray(at, at + 2)), column: Number(data.subarray(at + 2, at + 4)), text: data.subarray(at + 13, at + 13 + textLength).toString("utf8") });
          at += 13 + textLength;
        }
      }
      rest = rest.subarray(size);
    }
    return out;
  } catch {
    return null;
  }
}

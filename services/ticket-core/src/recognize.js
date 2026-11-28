// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// "I already have a ticket": from what a phone read off a paper or screen ticket to a scope the connection
// search can use.
//
// The photo itself never comes here. The app reads the text (and any barcode) on the device and sends only
// that. One of our own codes is verified and exact. Anything else is matched by its printed words against the
// catalogue, which also holds tickets we do not sell (KlimaTicket, Deutschlandticket, city day tickets).

import { plain } from "./core/bytes.js";
import { parseTicket } from "./core/token.js";
import { checkTicket } from "./core/validate.js";
import { resolveWindow, zoned } from "./core/time.js";
import { currentVersion } from "./products.js";
import { trustList } from "./trust.js";

function distance(a, b) {
  if (Math.abs(a.length - b.length) > 2) return 3;
  let previous = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i += 1) {
    const row = [i];
    for (let j = 1; j <= b.length; j += 1) {
      row[j] = Math.min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
    previous = row;
  }
  return previous[b.length];
}

// A printed word counts as found when the text has it, allowing one wrong letter in longer words (OCR).
function hasWord(word, words, joined) {
  if (words.has(word)) return true;
  if (word.length < 6) return false;
  if (joined.includes(word)) return true;
  const allowed = word.length >= 10 ? 2 : 1;
  for (const candidate of words) if (distance(word, candidate) <= allowed) return true;
  return false;
}

function hasPhrase(phrase, words, joined) {
  const parts = plain(phrase).split(" ").filter(Boolean);
  return parts.length > 0 && parts.every((p) => hasWord(p, words, joined));
}

/** Keywords: a list whose entries are a phrase or a list of alternative phrases. Every entry should be there. */
export function keywordsFor(version, operator) {
  if (version.keywords) return version.keywords;
  const words = plain(version.name.de).split(" ").filter((w) => w.length >= 3);
  return [...words, [operator.name, ...(operator.aliases ?? [])]];
}

const MONTHS = { jan: 1, feb: 2, mar: 3, mrz: 3, mar_: 3, apr: 4, mai: 5, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, okt: 10, oct: 10, nov: 11, dez: 12, dec: 12 };
const FROM = /(gultig ab|gilt ab|valid from|\bab\b|\bvon\b|\bfrom\b|beginn|start)\W*$/;
const UNTIL = /(gultig bis|valid until|valid to|\bbis\b|\buntil\b|\bto\b|ablauf|expires|ende)\W*$/;

/** Dates printed on the ticket: [{ year, month, day, hour, minute, role }] in reading order. */
export function findDates(text) {
  const flat = String(text).normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  const found = [];
  const add = (match, year, month, day) => {
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31 || year < 2000 || year > 2100) return;
    const before = flat.slice(Math.max(0, match.index - 24), match.index);
    const after = flat.slice(match.index + match[0].length, match.index + match[0].length + 16);
    const time = /^[\s,]*(?:um\s*|at\s*)?(\d{1,2})[:.](\d{2})(?!\d|\.\d)/.exec(after);
    found.push({
      index: match.index, year, month, day,
      hour: time && Number(time[1]) < 24 ? Number(time[1]) : null, minute: time && Number(time[2]) < 60 ? Number(time[2]) : null,
      role: UNTIL.test(before) ? "until" : FROM.test(before) ? "from" : null,
    });
  };
  for (const m of flat.matchAll(/(?<!\d)(\d{1,2})[./](\d{1,2})[./](\d{4}|\d{2})(?!\d)/g)) add(m, Number(m[3]), Number(m[2]), Number(m[1]));
  for (const m of flat.matchAll(/(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)/g)) add(m, Number(m[1]), Number(m[2]), Number(m[3]));
  for (const m of flat.matchAll(/(?<!\d)(\d{1,2})\.?\s+(jan|feb|mar|mrz|apr|mai|may|jun|jul|aug|sep|okt|oct|nov|dez|dec)[a-z]*\.?\s+(\d{4})/g)) {
    add(m, Number(m[3]), MONTHS[m[2]], Number(m[1]));
  }
  return found.sort((a, b) => a.index - b.index);
}

function moment(date, timeZone, endOfDay) {
  if (date.hour !== null) return zoned(date.year, date.month, date.day, date.hour, timeZone, date.minute ?? 0);
  return endOfDay ? zoned(date.year, date.month, date.day + 1, 0, timeZone) - 1000 : zoned(date.year, date.month, date.day, 0, timeZone);
}

/** First and last valid moment from the printed dates and the product's own time rule. */
export function windowFromText(text, validity, now = Date.now()) {
  const zone = validity.timeZone ?? "Europe/Vienna";
  const dates = findDates(text);
  let from = dates.find((d) => d.role === "from");
  let until = dates.find((d) => d.role === "until");
  const free = dates.filter((d) => d !== from && d !== until);
  if (!from && !until && free.length >= 2) [from, until] = [free[0], free[1]];
  else if (!from && free.length >= 1) from = free[0];
  const assumed = [];
  let fromMs = from ? moment(from, zone, false) : null;
  let untilMs = until ? moment(until, zone, true) : null;
  if (fromMs !== null && untilMs !== null && untilMs < fromMs) [fromMs, untilMs] = [untilMs, fromMs];
  if (fromMs === null) { fromMs = untilMs !== null ? Math.min(now, untilMs) : now; assumed.push("from"); }
  if (untilMs === null) { untilMs = resolveWindow(validity.time, fromMs, zone).until; assumed.push("until"); }
  return { from: fromMs, until: untilMs, assumed };
}

function barcodeFormat(code) {
  if (code.startsWith("PT1.")) return "publit";
  if (code.startsWith("#UT")) return "uic-918-3";
  if (/^[0-9a-f]{40,}$/i.test(code) && code.toLowerCase().startsWith("9e")) return "vdv";
  return "unknown";
}

/**
 * → { tickets: [verified own tickets], candidates: [{ productId, name, operator, confidence, entitlement, … }],
 *     barcodes: [{ format }] }, best candidate first.
 */
export async function recognise(store, { text = "", barcodes = [] }, now = Date.now()) {
  const out = { tickets: [], candidates: [], barcodes: [] };
  const trust = trustList(store, now);
  for (const code of barcodes.slice(0, 5)) {
    if (typeof code !== "string") continue;
    const format = barcodeFormat(code);
    out.barcodes.push({ format });
    if (format !== "publit" || !parseTicket(code)) continue;
    const result = await checkTicket(code.split("~")[0], { ...trust, products: trust.products }, { now });
    // A live ticket read from a photo has no fresh proof; for the search the signature is what counts.
    const signed = result.checks.some((c) => c.name === "signature" && c.ok);
    if (!signed || !result.ticket) continue;
    const product = trust.products[`${result.ticket.p}@${result.ticket.pv}`];
    if (!product) continue;
    out.tickets.push({
      verified: true, revoked: trust.revoked.includes(result.ticket.id), productId: result.ticket.p, name: product.name,
      entitlement: { source: "ticket", productId: result.ticket.p, version: result.ticket.pv,
        validFrom: result.ticket.nbf * 1000, validUntil: result.ticket.exp * 1000, od: result.ticket.od ?? null },
    });
  }

  const flat = plain(text);
  if (flat.length >= 3) {
    const words = new Set(flat.split(" "));
    const joined = flat.replaceAll(" ", "");
    for (const product of Object.values(store.data.products)) {
      const version = currentVersion(product);
      if (!version || version.status !== "published") continue;
      const operator = store.data.operators[product.operatorId];
      const keywords = keywordsFor(version, operator);
      const matched = keywords.filter((entry) => (Array.isArray(entry) ? entry : [entry]).some((p) => hasPhrase(p, words, joined)));
      const first = keywords[0];
      const firstFound = (Array.isArray(first) ? first : [first]).some((p) => hasPhrase(p, words, joined));
      const confidence = matched.length / keywords.length;
      if (!firstFound || confidence < 0.6) continue;
      const window = windowFromText(text, version.validity, now);
      out.candidates.push({
        productId: product.id, version: version.version, name: version.name, operator: operator.name, sellable: product.sellable,
        confidence: Number((confidence * (window.assumed.length === 2 ? 0.9 : 1)).toFixed(2)), matched: matched.length, of: keywords.length,
        assumed: window.assumed, approximate: Boolean(version.validity.approximate),
        entitlement: { source: "scan", productId: product.id, version: version.version, validFrom: window.from, validUntil: window.until, od: null },
      });
    }
    // More matched words win; among equals the more specific product (more keywords) wins.
    out.candidates.sort((a, b) => b.confidence - a.confidence || b.of - a.of);
    out.candidates = out.candidates.slice(0, 5);
  }
  return out;
}

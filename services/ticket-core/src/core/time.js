// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// From a product's time rule to the exact first and last moment of one ticket. The result is written into the
// ticket, so nobody has to interpret "day ticket" at the door: there are two timestamps.

function parts(ms, timeZone) {
  const out = {};
  for (const p of new Intl.DateTimeFormat("en-CA", {
    timeZone, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit",
  }).formatToParts(new Date(ms))) if (p.type !== "literal") out[p.type] = Number(p.value);
  return out;
}

/** Epoch milliseconds of a wall-clock time in a zone. Month and day may overflow (day 32, month 13). */
export function zoned(year, month, day, hour, timeZone, minute = 0) {
  const guess = Date.UTC(year, month - 1, day, hour, minute);
  const offset = (ms) => {
    const p = parts(ms, timeZone);
    return Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second) - Math.floor(ms / 1000) * 1000;
  };
  const first = guess - offset(guess);
  return guess - offset(first);
}

/** → { from, until } in epoch milliseconds. */
export { parts as localParts };

export function resolveWindow(time, startMs, timeZone = "Europe/Vienna") {
  if (time.type === "fixed") return { from: Date.parse(time.from), until: Date.parse(time.until) };
  if (time.type === "duration") return { from: startMs, until: startMs + time.minutes * 60000 };
  if (time.type === "calendar") {
    const p = parts(startMs, timeZone);
    const count = time.count ?? 1;
    const endHour = time.endHour ?? 0; // some day tickets run until 1:00 the next morning
    let until;
    if (time.unit === "day") until = zoned(p.year, p.month, p.day + count, endHour, timeZone);
    else if (time.unit === "month") until = zoned(p.year, p.month + count, 1, endHour, timeZone);
    else if (time.unit === "year") until = zoned(p.year + count, p.month, p.day, endHour, timeZone);
    else throw new Error(`unknown calendar unit ${time.unit}`);
    return { from: startMs, until: until - 1000 };
  }
  throw new Error(`unknown time rule ${time.type}`);
}

export function formatMoment(ms, timeZone, language = "de") {
  return new Intl.DateTimeFormat(language === "de" ? "de-AT" : "en-GB", {
    timeZone, day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit", hourCycle: "h23",
  }).format(new Date(ms));
}

// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Turns a ticket's machine-readable scope into sentences a customer and a conductor read the same way.
// The text is generated from the data, never typed by hand, so the two cannot drift apart.

import { formatMoment } from "./time.js";

const MODES = {
  de: { TRAM: "Straßenbahn", SUBWAY: "U-Bahn", BUS: "Bus", COACH: "Fernbus", FERRY: "Fähre", SUBURBAN: "S-Bahn",
    REGIONAL_RAIL: "Regionalzug", REGIONAL_FAST_RAIL: "Regionalexpress", LONG_DISTANCE: "Fernzug",
    HIGHSPEED_RAIL: "Hochgeschwindigkeitszug", NIGHT_RAIL: "Nachtzug", FUNICULAR: "Standseilbahn",
    AERIAL_LIFT: "Seilbahn", CABLE_CAR: "Kabelbahn", AIRPLANE: "Flug", OTHER: "Sonstige" },
  en: { TRAM: "tram", SUBWAY: "underground", BUS: "bus", COACH: "coach", FERRY: "ferry", SUBURBAN: "suburban rail",
    REGIONAL_RAIL: "regional train", REGIONAL_FAST_RAIL: "regional express", LONG_DISTANCE: "long-distance train",
    HIGHSPEED_RAIL: "high-speed train", NIGHT_RAIL: "night train", FUNICULAR: "funicular",
    AERIAL_LIFT: "cable car", CABLE_CAR: "cable tram", AIRPLANE: "flight", OTHER: "other" },
};

const COUNTRIES = {
  de: { AT: "Österreich", DE: "Deutschland", CH: "Schweiz", IT: "Italien", CZ: "Tschechien", HU: "Ungarn",
    SK: "Slowakei", SI: "Slowenien", FR: "Frankreich", NL: "Niederlande", BE: "Belgien", PL: "Polen", SE: "Schweden" },
  en: { AT: "Austria", DE: "Germany", CH: "Switzerland", IT: "Italy", CZ: "Czechia", HU: "Hungary", SK: "Slovakia",
    SI: "Slovenia", FR: "France", NL: "the Netherlands", BE: "Belgium", PL: "Poland", SE: "Sweden" },
};

const TEXT = {
  de: {
    from: "Gilt ab", until: "bis", everywhere: "im ganzen Netz der genannten Unternehmen", country: "ganz",
    zone: "Zone", stops: "an den Haltestellen", route: "Strecke", chosen: "zwischen den beim Kauf gewählten Haltestellen",
    anyOperator: "alle Verkehrsunternehmen im Gebiet", allModes: "alle öffentlichen Verkehrsmittel",
    unlimited: "Beliebig viele Fahrten", rides: (n) => (n === 1 ? "Eine Fahrt" : `${n} Fahrten`),
    rideOut: "Eine begonnene Fahrt darf beendet werden", noRideOut: "Die Fahrt muss vor Ablauf enden",
    klass: (n) => `${n}. Klasse`, personal: "Persönlich, nur mit Ausweis", transferable: "Übertragbar",
    approximate: "Vereinfachtes Modell aus öffentlichen Angaben, vom Herausgeber noch nicht bestätigt.",
    notMode: "nicht in", duration: (m) => (m % 1440 === 0 ? `${m / 1440 * 24} Stunden` : m % 60 === 0 ? `${m / 60} Stunden` : `${m} Minuten`),
    calendar: { day: (n) => (n === 1 ? "bis Betriebsschluss des Tages" : `${n} Kalendertage`), month: (n) => (n === 1 ? "bis Monatsende" : `${n} Kalendermonate`), year: (n) => (n === 1 ? "ein Jahr" : `${n} Jahre`) },
    afterStart: "ab Gültigkeitsbeginn",
  },
  en: {
    from: "Valid from", until: "until", everywhere: "on the whole network of the operators named", country: "all of",
    zone: "zone", stops: "at the stops", route: "route", chosen: "between the two stops chosen at purchase",
    anyOperator: "all public transport operators in the area", allModes: "all public transport",
    unlimited: "Unlimited rides", rides: (n) => (n === 1 ? "One ride" : `${n} rides`),
    rideOut: "A ride begun in time may be finished", noRideOut: "The ride must end before expiry",
    klass: (n) => (n === 1 ? "1st class" : "2nd class"), personal: "Personal, valid with ID only", transferable: "Transferable",
    approximate: "Simplified model from public information, not yet confirmed by the issuer.",
    notMode: "not on", duration: (m) => (m % 60 === 0 ? `${m / 60} hours` : `${m} minutes`),
    calendar: { day: (n) => (n === 1 ? "until the end of service that day" : `${n} calendar days`), month: (n) => (n === 1 ? "until the end of the month" : `${n} calendar months`), year: (n) => (n === 1 ? "one year" : `${n} years`) },
    afterStart: "from the start of validity",
  },
};

function local(value, language) {
  if (value && typeof value === "object") return value[language] ?? value.en ?? value.de ?? "";
  return value ?? "";
}

function areaText(rule, language, od) {
  const t = TEXT[language];
  switch (rule.type) {
    case "country": return `${t.country} ${COUNTRIES[language][rule.code] ?? rule.code}`;
    case "zone": return `${t.zone} ${local(rule.name, language) || rule.id}`;
    case "stops": return `${t.stops} ${rule.stops.map((s) => s.name ?? s.id).join(", ")}`;
    case "route": {
      const from = rule.from ?? od?.from;
      const to = rule.to ?? od?.to;
      return from && to ? `${t.route} ${from.name ?? from.id} – ${to.name ?? to.id}` : t.chosen;
    }
    default: return rule.type;
  }
}

/**
 * → { when, duration, where: [], operators, modes, notValid: [], conditions: [], note } in one language.
 * `window` ({ from, until } in ms) is given for an issued ticket and left out for a product in the catalogue.
 */
export function describeValidity(validity, { language = "de", window = null, operators = [], od = null } = {}) {
  const t = TEXT[language];
  const zone = validity.timeZone ?? "Europe/Vienna";
  const names = (ids) => ids.map((id) => operators.find((o) => o.id === id)?.name ?? id);
  const time = validity.time;
  const duration = time.type === "duration" ? `${t.duration(time.minutes)} ${t.afterStart}`
    : time.type === "calendar" ? t.calendar[time.unit](time.count ?? 1)
      : `${formatMoment(Date.parse(time.from), zone, language)} – ${formatMoment(Date.parse(time.until), zone, language)}`;
  const notValid = [];
  if (validity.modes?.except?.length) notValid.push(`${t.notMode} ${validity.modes.except.map((m) => MODES[language][m] ?? m).join(", ")}`);
  for (const rule of validity.except ?? []) {
    const label = local(rule.label, language);
    notValid.push(label || [...names(rule.operators ?? []), ...(rule.lines ?? []), ...(rule.modes ?? []).map((m) => MODES[language][m] ?? m)].join(", "));
  }
  const area = validity.area ?? [];
  return {
    when: window ? `${t.from} ${formatMoment(window.from, zone, language)} ${t.until} ${formatMoment(window.until, zone, language)} (${zone})` : null,
    duration,
    where: area.length ? area.map((r) => areaText(r, language, od)) : [t.everywhere],
    operators: Array.isArray(validity.operators) ? names(validity.operators).join(", ") : t.anyOperator,
    modes: validity.modes?.only ? validity.modes.only.map((m) => MODES[language][m] ?? m).join(", ") : t.allModes,
    notValid,
    conditions: [
      validity.rides === undefined || validity.rides === "unlimited" ? t.unlimited : t.rides(validity.rides),
      validity.rideOut === false ? t.noRideOut : t.rideOut,
      t.klass(validity.class ?? 2),
      validity.personal ? t.personal : t.transferable,
    ],
    note: validity.approximate ? t.approximate : null,
  };
}

const REASONS = {
  de: { covered: "Ticket gilt", no_ticket_needed: "Kein Ticket nötig", before_start: "Ticket gilt noch nicht",
    after_end: "Ticket ist abgelaufen", ends_after_end: "Fahrt endet nach Ablauf", mode: "Verkehrsmittel nicht enthalten",
    operator: "Unternehmen nicht enthalten", operator_unknown: "Unternehmen unbekannt, bitte prüfen",
    area: "Außerhalb des Geltungsbereichs", area_unknown: "Lage unklar, bitte prüfen", excepted: "Ausdrücklich ausgenommen",
    route: "Nicht auf der Strecke des Tickets", no_ticket: "Kein Ticket" },
  en: { covered: "Ticket valid", no_ticket_needed: "No ticket needed", before_start: "Ticket not valid yet",
    after_end: "Ticket has expired", ends_after_end: "Ride ends after expiry", mode: "Type of transport not included",
    operator: "Operator not included", operator_unknown: "Operator unknown, please check",
    area: "Outside the area of validity", area_unknown: "Location unclear, please check", excepted: "Explicitly excluded",
    route: "Not on the ticket's route", no_ticket: "No ticket" },
};

export function reasonText(result, language = "de") {
  const text = REASONS[language][result.reason] ?? result.reason;
  const detail = local(result.detail, language);
  return detail ? `${text}: ${detail}` : text;
}

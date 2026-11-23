// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Open ticket-link layer: for each leg of a journey, the best place to buy its ticket, sent through the shop's
// affiliate program when there is one. Any app may use it. No customer money and no personal data pass through
// here: the app sends operator names and the links it already has, and gets links back.
//
//   GET  /v1/partners   → { programs: [{ id, name, hosts, template }] }   Publit's active programs (for the app)
//   POST /v1/links      { legs: [{ index, operator, mode?, links?: { booking?, fares?, website? } }],
//                         partners?: { <program id>: <your own tracking template> }, app?: "<your app id>" }
//                       → { links: [{ leg, operator, url, source, partner, via }] }
//
// "Bring your own ID": a caller that sends its own template for a program earns the commission itself. Legs without
// one use Publit's template (PARTNER_TEMPLATES), and Publit's commission pays for running this service.
// "Share": an app without its own affiliate accounts sends `app`; its clicks on Publit's links carry that id as the
// network's sub-ID (Awin clickref, Partnerize pubref, Impact subId1, Tradedoubler epi), so the network's report
// shows each app's commission and Publit can pay out the agreed share.

import { ShopError } from "./shop.js";

// Tracking hosts each affiliate network uses. A template must point to one of them, so nobody can turn this
// service into an open redirect.
const NETWORK_HOSTS = {
  awin: ["awin1.com"],
  partnerize: ["prf.hn"],
  impact: ["sjv.io", "pxf.io", "evyy.net"],
  tradedoubler: ["tradedoubler.com"],
};

const TLDS = ["de", "com", "at", "ch", "fr", "it", "es", "nl", "pl", "se", "cz", "co.uk", "be", "dk"];

export const PROGRAMS = [
  { id: "db", name: "Deutsche Bahn", network: "awin", hosts: ["bahn.de", "bahn.com"] },
  { id: "flixbus", name: "FlixBus", network: "awin", hosts: [...TLDS.map((t) => `flixbus.${t}`), "flixtrain.de", "flixtrain.com"] },
  { id: "trainline", name: "Trainline", network: "partnerize",
    hosts: ["thetrainline.com", "trainline.eu", "trainline.de", "trainline.fr", "trainline.it", "trainline.es"] },
  { id: "omio", name: "Omio", network: "impact", hosts: TLDS.map((t) => `omio.${t}`) },
  { id: "sncf", name: "SNCF Connect", network: "awin", hosts: ["sncf-connect.com"] },
  { id: "eurostar", name: "Eurostar", network: "awin", hosts: ["eurostar.com"] },
];

// Shops of large operators whose feeds publish no ticket URL. Keys are operator names in lower case without
// accents; a key matches when all its words appear in the operator name (the longest match wins).
export const KNOWN_SHOPS = {
  "u-bahn munchen": "https://www.mvg.de/tickets-tarife.html",
  mvg: "https://www.mvg.de/tickets-tarife.html",
  "s-bahn munchen": "https://www.mvv-muenchen.de/",
  db: "https://int.bahn.de",
  "deutsche bahn": "https://int.bahn.de",
  obb: "https://tickets.oebb.at",
  "wiener linien": "https://shop.wienerlinien.at",
  trenitalia: "https://www.trenitalia.com",
  sbb: "https://www.sbb.ch",
  flixbus: "https://www.flixbus.com",
  flixtrain: "https://www.flixtrain.com",
  sncf: "https://www.sncf-connect.com",
  eurostar: "https://www.eurostar.com",
};

// The network's own field for a publisher sub-ID.
export function withSubId(network, link, app) {
  if (!app) return link;
  if (network === "partnerize") {
    return link.includes("/destination:") ? link.replace("/destination:", `/pubref:${app}/destination:`) : link;
  }
  const field = { awin: "clickref", impact: "subId1", tradedoubler: "epi" }[network];
  if (!field) return link;
  const url = new URL(link);
  url.searchParams.set(field, app);
  return url.toString();
}

const APP_ID = /^[a-z0-9][a-z0-9-]{0,39}$/;
const MAX_LEGS = 20;
const SOURCES = ["booking", "fares", "website"];

export function operatorKey(name) {
  return String(name ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().split(/\s+/).filter(Boolean).join(" ");
}

export function knownShop(operator) {
  const words = new Set(operatorKey(operator).split(" "));
  let best = null;
  for (const [key, url] of Object.entries(KNOWN_SHOPS)) {
    if (key.split(" ").every((w) => words.has(w)) && (!best || key.length > best.key.length)) best = { key, url };
  }
  return best?.url ?? null;
}

function hostMatches(host, list) {
  return list.some((h) => host === h || host.endsWith("." + h));
}

export function webURL(value) {
  if (typeof value !== "string" || value.length > 2000) return null;
  try {
    const url = new URL(value.trim());
    return url.protocol === "https:" || url.protocol === "http:" ? url : null;
  } catch {
    return null;
  }
}

/** A tracking template is valid when it is https, on its network's host, and has exactly one {url}. */
export function validTemplate(program, template) {
  if (typeof template !== "string" || template.length > 500) return false;
  if (template.split("{url}").length !== 2) return false;
  const url = webURL(template.replace("{url}", "x"));
  return !!url && url.protocol === "https:" && hostMatches(url.hostname.toLowerCase(), NETWORK_HOSTS[program.network] ?? []);
}

/** Publit's own templates from the PARTNER_TEMPLATES variable (JSON: { "<program id>": "<template>" }). */
export function publitTemplates(env) {
  let raw = {};
  try {
    raw = JSON.parse(env.PARTNER_TEMPLATES || "{}");
  } catch {
    return {};
  }
  const out = {};
  for (const p of PROGRAMS) if (validTemplate(p, raw?.[p.id])) out[p.id] = raw[p.id];
  return out;
}

export function programFor(url) {
  const host = url.hostname.toLowerCase();
  return PROGRAMS.find((p) => hostMatches(host, p.hosts)) ?? null;
}

export function wrap(url, template) {
  return template.replace("{url}", encodeURIComponent(url.toString()));
}

export function partners(env) {
  const templates = publitTemplates(env);
  return {
    programs: PROGRAMS.filter((p) => templates[p.id]).map((p) => ({ id: p.id, name: p.name, hosts: p.hosts, template: templates[p.id] })),
  };
}

export function parseLinkRequest(body) {
  if (!body || !Array.isArray(body.legs) || body.legs.length === 0 || body.legs.length > MAX_LEGS) {
    throw new ShopError(400, "invalid", `legs must be a list of 1 to ${MAX_LEGS} legs`);
  }
  const legs = body.legs.map((leg, i) => {
    if (!leg || typeof leg !== "object") throw new ShopError(400, "invalid", `leg ${i} is not an object`);
    const operator = typeof leg.operator === "string" ? leg.operator.trim().slice(0, 200) : "";
    const links = {};
    for (const s of SOURCES) links[s] = webURL(leg.links?.[s]);
    return { index: Number.isInteger(leg.index) ? leg.index : i, operator, links };
  });
  const own = {};
  if (body.partners && typeof body.partners === "object") {
    for (const p of PROGRAMS) {
      const t = body.partners[p.id];
      if (t === undefined) continue;
      if (!validTemplate(p, t)) throw new ShopError(400, "invalid", `partners.${p.id} is not a valid ${p.network} tracking link with {url}`);
      own[p.id] = t;
    }
  }
  let app = null;
  if (body.app !== undefined && body.app !== null) {
    if (typeof body.app !== "string" || !APP_ID.test(body.app)) {
      throw new ShopError(400, "invalid", "app must be 1 to 40 lower-case letters, digits or dashes");
    }
    app = body.app;
  }
  return { legs, partners: own, app };
}

/** One link per leg: the feed's booking link, fare page or website, else a known shop; wrapped when possible. */
export function findLinks(body, env) {
  const request = parseLinkRequest(body);
  const publit = publitTemplates(env);
  const links = [];
  for (const leg of request.legs) {
    let url = null;
    let source = null;
    for (const s of SOURCES) {
      if (leg.links[s]) {
        url = leg.links[s];
        source = s;
        break;
      }
    }
    if (!url) {
      const shop = knownShop(leg.operator);
      if (shop) {
        url = new URL(shop);
        source = "fares";
      }
    }
    if (!url) continue;
    const program = programFor(url);
    const own = program && request.partners[program.id];
    const template = own ?? (program && publit[program.id]);
    const link = template ? wrap(url, template) : null;
    links.push({
      leg: leg.index,
      operator: leg.operator || null,
      url: link ? (own ? link : withSubId(program.network, link, request.app)) : url.toString(),
      source,
      partner: template ? program.name : null,
      via: template ? (own ? "caller" : "publit") : null,
    });
  }
  return { links };
}

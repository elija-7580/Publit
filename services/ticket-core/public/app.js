// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// The demo console. Four things a visitor can try: bring an operator on board, buy a ticket, check it like a
// conductor (with the very code the server uses, offline if wanted), and search connections for a ticket
// that was only photographed. No build step, no framework.

import { present, generateKeyPair, deviceKeyFromJwk, parseTicket } from "/core/token.js";
import { openTrustList, checkTicket } from "/core/validate.js";
import { describeValidity } from "/core/describe.js";
import { b64u, encoder } from "/core/bytes.js";

const $ = (id) => document.getElementById(id);
const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

const TEXT = {
  de: {
    demoChip: "Demo", tabOverview: "Überblick", tabOperator: "Betreiber", tabBuy: "Kaufen", tabCheck: "Kontrolle", tabScan: "Ticket scannen", tabApi: "API",
    heroTitle: "Ein Backend für die Tickets aller Verkehrsunternehmen.",
    heroLead: "Jedes Unternehmen kommt in Minuten dazu, auch ohne eigenes Vertriebssystem. Jedes Ticket trägt maschinenlesbar, wo und ab wann es gilt. Kontrolliert wird mit einem signierten Code, der ohne Netz prüfbar ist.",
    s1h: "Betreiber kommt dazu", s1p: "Anmelden, freigeben, Tickets aus Vorlagen anlegen. Kein Programmieren, kein Systemwechsel.",
    s2h: "Kundin kauft", s2p: "Das Ticket sagt in Klartext und in Daten, wo es gilt, wo nicht und ab wann.",
    s3h: "Schaffner prüft", s3p: "Signierter QR-Code, Prüfung ohne Netz, Schutz gegen Screenshots und Fälschungen.",
    s4h: "Ticket fotografieren", s4p: "Vorhandenes Ticket erkennen und nur Verbindungen zeigen, die es abdeckt.",
    demoNote: "Demo-Daten. Alpenland Bus ist erfunden. Die echten Unternehmen stehen nur als Verzeichniseintrag hier, es gibt keine Verträge und nichts von ihnen wird verkauft. KlimaTicket, Deutschlandticket und Wiener Stundentickets sind vereinfacht aus öffentlichen Angaben nachgebildet.",
    opTitle: "Betreiber-Onboarding", opLead: "Ein Unternehmen meldet sich an, Publit prüft die Firma und schaltet frei. Danach legt es seine Tickets aus Vorlagen an. Jede Änderung ist eine neue, unveränderliche Version.",
    opApplyH: "1. Unternehmen anmelden", fName: "Name des Unternehmens", fCountry: "Land", fEmail: "Kontakt-E-Mail", fLevel: "Wie will es verkaufen?",
    lvHosted: "Ohne eigenes System: Publit stellt die Tickets aus", lvLink: "Nur Link zum eigenen Shop", lvApi: "Über das eigene Vertriebssystem (Adapter)",
    opApply: "Anmelden", opDirH: "Verzeichnis", pending: "wartet auf Freigabe", active: "aktiv", listed: "nur gelistet", suspended: "gesperrt",
    approve: "Als Publit freigeben", applied: "Angemeldet. API-Schlüssel (wird nur einmal gezeigt):", approved: "Freigegeben. Signaturschlüssel erzeugt:",
    prH: "2. Ticket anlegen", fOperator: "Unternehmen", fTemplate: "Vorlage", fProductName: "Name", fPrice: "Preis (€)", fHours: "Stunden", fArea: "Wo gilt es?",
    arNetwork: "Im ganzen Netz des Unternehmens", arCountry: "In ganz Österreich (nur eigene Fahrzeuge)", arZone: "Nur in der Zone Salzkammergut (Beispiel)",
    prSave: "Veröffentlichen", prListH: "Tickets dieses Unternehmens", stH: "Abrechnung", noOperator: "Noch kein freigeschaltetes Unternehmen.",
    stSold: "verkauft", stRefunded: "erstattet", stGross: "Umsatz", stFee: "Provision Publit", stNet: "Auszahlung",
    version: "Version", data: "So steht es in den Daten", retire: "Aus dem Verkauf nehmen", notOnSale: "nicht im Verkauf",
    kWhen: "Zeitraum", kDuration: "Dauer", kWhere: "Gilt in", kOperators: "Bei", kModes: "Fahrzeuge", kNot: "Gilt nicht", kTerms: "Bedingungen", kHolder: "Person",
    buyTitle: "Kaufen", buyLead: "So sieht es für die Kundin aus. Die Zahlung ist hier ein Demo-Schritt, es fließt kein Geld.",
    buyCatalog: "Tickets im Verkauf", buyWallet: "Meine Tickets", buy: "Kaufen (Demo-Zahlung)", from: "Von", to: "Nach", holderName: "Name", birthYear: "Geburtsjahr",
    liveOpt: "Live-Code (Screenshots funktionieren nicht)", walletEmpty: "Noch kein Ticket gekauft.", show: "Bei der Kontrolle vorzeigen", refund: "Erstatten",
    revoked: "erstattet", liveNote: "Live-Code, erneuert sich alle 10 Sekunden", map: "Karte", approx: "ungefähr",
    chkTitle: "Kontrolle", chkLead: "Das Prüfgerät lädt einmal die signierte Vertrauensliste und prüft danach ohne Netz. Hier läuft dieselbe Prüfung im Browser.",
    chkWhere: "Wo steht der Schaffner?", fMode: "Fahrzeug", fStop: "Haltestelle", anyStop: "egal", chkSync: "Liste aktualisieren", chkOffline: "Offline prüfen",
    chkScan: "Code prüfen", chkCamera: "Kamera starten", chkCheck: "Prüfen", chkWallet: "Tickets aus dieser Demo", chkIdle: "Noch nichts geprüft.",
    trustNone: "Noch keine Vertrauensliste geladen.", trustState: (n, k, r, t) => `Vertrauensliste vom ${t}: ${n} Aussteller, ${k} Schlüssel, ${r} gesperrte Tickets.`,
    trustOffline: "Offline: es wird nur die gespeicherte Liste verwendet.", useShow: "vorzeigen", useShot: "alter Screenshot", useForged: "gefälscht (+1 Tag)",
    vValid: "GÜLTIG", vInvalid: "UNGÜLTIG", vCheck: "PRÜFEN", noCamera: "Keine Kamera verfügbar. Code einfügen oder ein Demo-Ticket wählen.",
    scTitle: "Ticket scannen", scLead: "Ein Foto vom Papier- oder Handyticket genügt. Der Text wird auf dem Gerät gelesen, das Foto verlässt es nicht. Danach zeigt die Suche, welche Verbindungen das Ticket abdeckt.",
    scPhoto: "1. Ticket fotografieren", scUpload: "Foto aufnehmen oder auswählen", scText: "Gelesener Text (änderbar)", scRecognise: "Ticket erkennen",
    scSearch: "2. Verbindungen für dieses Ticket", fRoute: "Strecke", fTicket: "Mein Ticket", scGo: "Verbindungen suchen", scOnly: "Nur Verbindungen, die mein Ticket ganz abdeckt",
    noTicket: "Kein Ticket", scanned: "Erkannt", bought: "Gekauft", ocrLoad: "Texterkennung wird geladen …", ocrRun: (p) => `Text wird gelesen … ${p} %`,
    ocrDone: "Text gelesen.", ocrFail: "Texterkennung nicht verfügbar. Der Text des Musters wurde eingesetzt.", ocrFailOwn: "Texterkennung nicht verfügbar. Bitte den Text eintippen.",
    notRecognised: "Kein bekanntes Ticket erkannt.", confidence: "Treffer", assumedFrom: "Beginn nicht aufgedruckt: ab jetzt angenommen.", assumedUntil: "Ende nicht aufgedruckt: aus der Ticketregel berechnet.",
    verifiedCode: "Signierter Code geprüft: Angaben exakt.", full: "Ticket deckt alles", partial: (n) => `${n} Abschnitt${n === 1 ? "" : "e"} ohne Ticket`, none: "Ticket gilt hier nicht", unknown: "bitte prüfen",
    extra: "dazu", addOn: "Dazu kaufbar", nothingFull: "Keine Verbindung wird ganz abgedeckt.", walk: "Fußweg", min: "Min.",
    apiTitle: "API", apiLead: "Alles in dieser Demo läuft über dieselbe offene HTTP-Schnittstelle, die Apps und Betreiber nutzen. Die vollständige Beschreibung steht in der README im Repository.",
    footer: "Publit Ticket Core, Prototyp. Quelloffen unter AGPL-3.0. Demo-Daten, keine echten Tickets.",
    error: "Das hat nicht geklappt", offlineNoApi: "Offline-Modus ist an.",
  },
  en: {
    demoChip: "Demo", tabOverview: "Overview", tabOperator: "Operators", tabBuy: "Buy", tabCheck: "Inspection", tabScan: "Scan a ticket", tabApi: "API",
    heroTitle: "One backend for every operator's tickets.",
    heroLead: "Any operator joins in minutes, even without a sales system of its own. Every ticket states in data where and from when it is valid. Inspection uses a signed code that can be checked without a network.",
    s1h: "An operator joins", s1p: "Apply, get approved, create tickets from templates. No programming, no change of systems.",
    s2h: "A customer buys", s2p: "The ticket says in plain words and in data where it is valid, where not, and from when.",
    s3h: "A conductor checks", s3p: "Signed QR code, checked without a network, safe against screenshots and forgery.",
    s4h: "Photograph a ticket", s4p: "Recognise a ticket someone already has and show only the connections it covers.",
    demoNote: "Demo data. Alpenland Bus is invented. The real companies are directory entries only: there are no contracts and nothing of theirs is sold here. KlimaTicket, Deutschlandticket and the Vienna hour tickets are simplified models from public information.",
    opTitle: "Operator onboarding", opLead: "A company applies, Publit checks it and switches it on. Then it creates its tickets from templates. Every change is a new version that never changes again.",
    opApplyH: "1. Register a company", fName: "Company name", fCountry: "Country", fEmail: "Contact e-mail", fLevel: "How does it want to sell?",
    lvHosted: "No system of its own: Publit issues the tickets", lvLink: "Only a link to its own shop", lvApi: "Through its own sales system (adapter)",
    opApply: "Apply", opDirH: "Directory", pending: "awaiting approval", active: "active", listed: "listed only", suspended: "suspended",
    approve: "Approve as Publit", applied: "Applied. API key (shown only once):", approved: "Approved. Signing key created:",
    prH: "2. Create a ticket", fOperator: "Operator", fTemplate: "Template", fProductName: "Name", fPrice: "Price (€)", fHours: "Hours", fArea: "Where is it valid?",
    arNetwork: "On the operator's whole network", arCountry: "All of Austria (own vehicles only)", arZone: "Only in the Salzkammergut zone (example)",
    prSave: "Publish", prListH: "This operator's tickets", stH: "Statement", noOperator: "No approved operator yet.",
    stSold: "sold", stRefunded: "refunded", stGross: "Sales", stFee: "Publit commission", stNet: "Payout",
    version: "Version", data: "How it is stored", retire: "Take off sale", notOnSale: "not on sale",
    kWhen: "Period", kDuration: "Duration", kWhere: "Valid in", kOperators: "With", kModes: "Vehicles", kNot: "Not valid", kTerms: "Terms", kHolder: "Holder",
    buyTitle: "Buy", buyLead: "What the customer sees. Payment is a demo step here, no money moves.",
    buyCatalog: "Tickets on sale", buyWallet: "My tickets", buy: "Buy (demo payment)", from: "From", to: "To", holderName: "Name", birthYear: "Year of birth",
    liveOpt: "Live code (screenshots do not work)", walletEmpty: "No ticket bought yet.", show: "Show at inspection", refund: "Refund",
    revoked: "refunded", liveNote: "Live code, renewed every 10 seconds", map: "Map", approx: "approximate",
    chkTitle: "Inspection", chkLead: "The checking device loads the signed trust list once and then checks without a network. The same check runs here in the browser.",
    chkWhere: "Where is the conductor?", fMode: "Vehicle", fStop: "Stop", anyStop: "any", chkSync: "Update list", chkOffline: "Check offline",
    chkScan: "Check a code", chkCamera: "Start camera", chkCheck: "Check", chkWallet: "Tickets from this demo", chkIdle: "Nothing checked yet.",
    trustNone: "No trust list loaded yet.", trustState: (n, k, r, t) => `Trust list of ${t}: ${n} issuers, ${k} keys, ${r} revoked tickets.`,
    trustOffline: "Offline: only the stored list is used.", useShow: "show", useShot: "old screenshot", useForged: "forged (+1 day)",
    vValid: "VALID", vInvalid: "NOT VALID", vCheck: "CHECK", noCamera: "No camera available. Paste a code or pick a demo ticket.",
    scTitle: "Scan a ticket", scLead: "A photo of the paper or phone ticket is enough. The text is read on the device, the photo never leaves it. The search then shows which connections the ticket covers.",
    scPhoto: "1. Photograph the ticket", scUpload: "Take or choose a photo", scText: "Text read (editable)", scRecognise: "Recognise ticket",
    scSearch: "2. Connections for this ticket", fRoute: "Route", fTicket: "My ticket", scGo: "Search connections", scOnly: "Only connections my ticket covers completely",
    noTicket: "No ticket", scanned: "Recognised", bought: "Bought", ocrLoad: "Loading text recognition …", ocrRun: (p) => `Reading text … ${p} %`,
    ocrDone: "Text read.", ocrFail: "Text recognition is not available. The sample's text was filled in.", ocrFailOwn: "Text recognition is not available. Please type the text.",
    notRecognised: "No known ticket recognised.", confidence: "match", assumedFrom: "No start printed: assumed from now.", assumedUntil: "No end printed: computed from the ticket's rule.",
    verifiedCode: "Signed code verified: exact.", full: "Ticket covers everything", partial: (n) => `${n} part${n === 1 ? "" : "s"} without a ticket`, none: "Ticket not valid here", unknown: "please check",
    extra: "plus", addOn: "Can be added", nothingFull: "No connection is covered completely.", walk: "walk", min: "min",
    apiTitle: "API", apiLead: "Everything in this demo runs on the same open HTTP interface that apps and operators use. The full description is in the README in the repository.",
    footer: "Publit Ticket Core, prototype. Open source under AGPL-3.0. Demo data, no real tickets.",
    error: "That did not work", offlineNoApi: "Offline mode is on.",
  },
};

const VERDICT = {
  de: { valid: "Ticket gilt.", check_id: "Persönliches Ticket: Ausweis vergleichen.", scope_operator_unknown: "Unternehmen nicht im Verzeichnis: Geltung von Hand prüfen.",
    scope_area_unknown: "Lage der Haltestelle unbekannt: Geltung von Hand prüfen.", scope_route_between: "Streckenticket: liegt dieser Halt auf der Strecke?",
    scope_area: "Gilt hier nicht: außerhalb des Gebiets.", scope_operator: "Gilt nicht bei diesem Unternehmen.", scope_mode: "Gilt nicht in diesem Verkehrsmittel.",
    scope_excepted: "Hier ausdrücklich ausgenommen.", scope_route: "Nicht auf der Strecke des Tickets.", not_a_ticket: "Kein Ticket dieses Systems.",
    unknown_issuer: "Aussteller unbekannt.", issuer_suspended: "Aussteller gesperrt.", key_not_valid: "Signaturschlüssel war bei Ausstellung nicht gültig.",
    signature_bad: "Signatur falsch: Ticket verändert oder gefälscht.", product_unknown: "Produkt oder Geltungsbereich passt nicht zum Aussteller.",
    revoked: "Ticket wurde erstattet oder gesperrt.", live_missing: "Kein Live-Code: vermutlich ein Screenshot.", live_bad: "Live-Code stammt nicht vom Gerät des Käufers.",
    live_stale: "Live-Code ist zu alt: vermutlich ein Screenshot.", not_yet_valid: "Ticket gilt noch nicht.", expired: "Ticket ist abgelaufen." },
  en: { valid: "Ticket is valid.", check_id: "Personal ticket: compare with ID.", scope_operator_unknown: "Operator not in the directory: check by hand.",
    scope_area_unknown: "Stop position unknown: check by hand.", scope_route_between: "Route ticket: is this stop on the route?",
    scope_area: "Not valid here: outside the area.", scope_operator: "Not valid with this operator.", scope_mode: "Not valid on this type of transport.",
    scope_excepted: "Explicitly excluded here.", scope_route: "Not on the ticket's route.", not_a_ticket: "Not a ticket of this system.",
    unknown_issuer: "Unknown issuer.", issuer_suspended: "Issuer suspended.", key_not_valid: "Signing key was not valid when the ticket was issued.",
    signature_bad: "Wrong signature: ticket changed or forged.", product_unknown: "Product or scope does not match the issuer.",
    revoked: "Ticket was refunded or blocked.", live_missing: "No live code: probably a screenshot.", live_bad: "Live code is not from the buyer's device.",
    live_stale: "Live code is too old: probably a screenshot.", not_yet_valid: "Ticket is not valid yet.", expired: "Ticket has expired." },
};
const CHECKS = {
  de: { issuer: "Aussteller bekannt", signature: "Signatur stimmt", product: "Produkt und Geltungsbereich unverändert", revocation: "Nicht gesperrt", live: "Live-Code vom Gerät des Käufers", time: "Im Gültigkeitszeitraum", scope: "Gilt in diesem Fahrzeug" },
  en: { issuer: "Issuer known", signature: "Signature correct", product: "Product and scope unchanged", revocation: "Not revoked", live: "Live code from the buyer's device", time: "Within the period of validity", scope: "Valid on this vehicle" },
};
const MODES = { BUS: ["Bus", "Bus"], TRAM: ["Straßenbahn", "Tram"], SUBWAY: ["U-Bahn", "Underground"], SUBURBAN: ["S-Bahn", "Suburban rail"],
  REGIONAL_RAIL: ["Regionalzug", "Regional train"], REGIONAL_FAST_RAIL: ["Regionalexpress", "Regional express"], LONG_DISTANCE: ["Fernzug", "Long-distance train"],
  HIGHSPEED_RAIL: ["Schnellzug", "High-speed train"], COACH: ["Fernbus", "Coach"] };
const SALZKAMMERGUT = [[13.0, 47.76], [13.0, 47.85], [13.2, 47.9], [13.6, 47.88], [13.75, 47.75], [13.6, 47.6], [13.25, 47.62], [13.05, 47.7]];
const STOPS = [
  { stopId: "demo:salzburg-hbf", name: "Salzburg Hauptbahnhof", lat: 47.8129, lon: 13.0458, country: "AT" },
  { stopId: "demo:fuschl", name: "Fuschl am See Ortsmitte", lat: 47.7944, lon: 13.3046, country: "AT" },
  { stopId: "demo:wien-stephansplatz", name: "Wien Stephansplatz", lat: 48.2085, lon: 16.3725, country: "AT" },
  { stopId: "demo:flughafen-wien", name: "Flughafen Wien", lat: 48.1207, lon: 16.5631, country: "AT" },
  { stopId: "demo:muenchen-hbf", name: "München Hauptbahnhof", lat: 48.1402, lon: 11.5583, country: "DE" },
];
const ROUTES = [["wien", "salzburg"], ["wien", "flughafen"], ["wien", "muenchen"], ["salzburg", "muenchen"], ["salzburg", "fuschl"]];

const state = {
  lang: localStorage.getItem("ptc-lang") ?? ((navigator.language ?? "de").startsWith("de") ? "de" : "en"),
  demo: null, operators: [], products: [], templates: [], wallet: JSON.parse(localStorage.getItem("ptc-wallet") ?? "[]"),
  trust: null, root: null, scanned: null, journeys: null,
};
const t = (key, ...args) => { const v = TEXT[state.lang][key]; return typeof v === "function" ? v(...args) : v ?? key; };
const pick = (value) => (value && typeof value === "object" ? value[state.lang] ?? value.de : value);
const money = (amount, currency = "EUR") => new Intl.NumberFormat(state.lang === "de" ? "de-AT" : "en-GB", { style: "currency", currency }).format(amount / 100);
const clock = (iso) => new Intl.DateTimeFormat(state.lang === "de" ? "de-AT" : "en-GB", { hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
const saveWallet = () => localStorage.setItem("ptc-wallet", JSON.stringify(state.wallet));

async function api(method, path, body, key) {
  if ($("offline").checked) throw new Error(t("offlineNoApi"));
  const response = await fetch(path, { method, headers: { "content-type": "application/json", ...(key ? { authorization: `Bearer ${key}` } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.message ?? `${response.status}`);
  return data;
}
const fail = (target, error) => { target.innerHTML = `<div class="box bad">${esc(t("error"))}: ${esc(error.message)}</div>`; };

function scopeList(d, holder) {
  const rows = [[t("kWhen"), d.when], [t("kDuration"), d.when ? null : d.duration], [t("kWhere"), d.where.join("; ")], [t("kOperators"), d.operators], [t("kModes"), d.modes],
    [t("kNot"), d.notValid.join("; "), "no"], [t("kTerms"), d.conditions.join(" · ")], [t("kHolder"), holder]];
  return `<ul class="scope">${rows.filter((r) => r[1]).map((r) => `<li><span>${esc(r[0])}</span><span class="${r[2] ?? ""}">${esc(r[1])}</span></li>`).join("")}</ul>${d.note ? `<p class="small">${esc(d.note)}</p>` : ""}`;
}

// ---- language and tabs -------------------------------------------------------------------------------------
function applyLanguage() {
  document.documentElement.lang = state.lang;
  for (const el of document.querySelectorAll("[data-t]")) el.textContent = t(el.dataset.t);
  $("lang").textContent = state.lang === "de" ? "EN" : "DE";
  $("ctx-mode").innerHTML = Object.entries(MODES).map(([id, names]) => `<option value="${id}">${names[state.lang === "de" ? 0 : 1]}</option>`).join("");
  $("ctx-stop").innerHTML = `<option value="">${t("anyStop")}</option>${STOPS.map((s, i) => `<option value="${i}">${esc(s.name)}</option>`).join("")}`;
  renderAll();
}
function go(tab) {
  for (const el of document.querySelectorAll(".tab")) el.classList.toggle("on", el.id === tab);
  for (const el of document.querySelectorAll("#tabs button")) el.classList.toggle("on", el.dataset.tab === tab);
  history.replaceState(null, "", `#${tab}`);
  window.scrollTo({ top: 0 });
}

// ---- operators ---------------------------------------------------------------------------------------------
const keyFor = (operatorId) => state.demo?.operatorKeys[operatorId];
async function reload() {
  [state.operators, state.products, state.templates, state.demo] = await Promise.all([
    api("GET", "/v1/operators").then((r) => r.operators), api("GET", "/v1/products").then((r) => r.products),
    api("GET", "/v1/templates").then((r) => r.templates), api("GET", "/v1/demo").catch(() => ({ operatorKeys: {}, places: [], adminToken: null })),
  ]);
  renderAll();
}

function renderOperators() {
  const chip = { active: "ok", pending: "ask", suspended: "bad", listed: "" };
  $("op-directory").innerHTML = state.operators.map((o) => `<div class="item"><span>${esc(o.name)} <span class="small">${esc(o.country)}</span></span>
    <span>${o.status === "pending" && state.demo?.adminToken ? `<button class="ghost" data-approve="${esc(o.id)}">${esc(t("approve"))}</button> ` : ""}<span class="chip ${chip[o.status]}">${esc(t(o.status))}</span></span></div>`).join("");
  const mine = state.operators.filter((o) => o.status === "active" && keyFor(o.id));
  const current = $("pr-operator").value;
  $("pr-operator").innerHTML = mine.map((o) => `<option value="${esc(o.id)}">${esc(o.name)}</option>`).join("") || `<option value="">${esc(t("noOperator"))}</option>`;
  if (mine.some((o) => o.id === current)) $("pr-operator").value = current;
  const template = $("pr-template").value;
  $("pr-template").innerHTML = state.templates.map((x) => `<option value="${x.id}">${esc(pick(x.name))}</option>`).join("");
  if (template) $("pr-template").value = template;
  $("pr-hours-wrap").hidden = $("pr-template").value !== "hours";
  const names = state.trust?.operators ?? state.operators;
  const ctx = $("ctx-operator").value;
  $("ctx-operator").innerHTML = names.map((o) => `<option value="${esc(o.id)}">${esc(o.name)}</option>`).join("");
  $("ctx-operator").value = names.some((o) => o.id === ctx) ? ctx : names.find((o) => o.id === "alpenland-bus")?.id ?? names[0]?.id ?? "";
  renderOperatorProducts();
}

async function renderOperatorProducts() {
  const id = $("pr-operator").value;
  if (!id || !keyFor(id) || $("offline").checked) { $("pr-list").innerHTML = ""; $("statement").innerHTML = ""; return; }
  try {
    const [{ products }, statement] = await Promise.all([api("GET", "/v1/operator/products", undefined, keyFor(id)), api("GET", "/v1/operator/statement", undefined, keyFor(id))]);
    $("pr-list").innerHTML = products.map((p) => `<div class="product"><header><strong>${esc(pick(p.name))}</strong>
        <span><span class="chip ${p.status === "published" ? "ok" : ""}">${esc(t("version"))} ${p.version}${p.status === "published" ? "" : ` · ${esc(t("notOnSale"))}`}</span> <span class="price">${p.price ? money(p.price.amount, p.price.currency) : ""}</span></span></header>
      ${scopeList(p.description[state.lang])}
      <details><summary>${esc(t("data"))} · <code>${esc(p.hash)}</code></summary><pre>${esc(JSON.stringify(p.validity, null, 2))}</pre></details>
      ${p.status === "published" ? `<div><button class="ghost" data-retire="${esc(p.id)}">${esc(t("retire"))}</button></div>` : ""}</div>`).join("");
    const s = statement.total;
    $("statement").innerHTML = `<div class="item"><span>${s.tickets} ${esc(t("stSold"))}, ${s.refunded} ${esc(t("stRefunded"))}</span><span>${esc(t("stGross"))} ${money(s.gross)}</span></div>
      <div class="item"><span>${esc(t("stFee"))} (${statement.commissionBps / 100} %)</span><span>− ${money(s.commission)}</span></div>
      <div class="item"><strong>${esc(t("stNet"))}</strong><strong>${money(s.net)}</strong></div>`;
  } catch (error) { fail($("pr-list"), error); }
}

async function applyOperator() {
  const out = $("op-result");
  try {
    const applied = await api("POST", "/v1/operators/apply", { name: $("op-name").value, country: $("op-country").value.toUpperCase(), contactEmail: $("op-email").value, level: $("op-level").value });
    await api("POST", "/v1/demo/remember-key", { apiKey: applied.apiKey });
    out.innerHTML = `<div class="box ask">${esc(t("applied"))}<br><code>${esc(applied.apiKey)}</code><br><br><button class="primary" data-approve="${esc(applied.operator.id)}">${esc(t("approve"))}</button></div>`;
    await reload();
  } catch (error) { fail(out, error); }
}
async function approve(id) {
  try {
    const { operator } = await api("POST", `/v1/admin/operators/${id}/approve`, {}, state.demo.adminToken);
    $("op-result").innerHTML = `<div class="box ok">${esc(operator.name)}: ${esc(t("approved"))} <code>${esc(operator.keys.at(-1)?.kid ?? "–")}</code></div>`;
    await reload();
    $("pr-operator").value = id;
    renderOperatorProducts();
    syncTrust();
  } catch (error) { fail($("op-result"), error); }
}
async function saveProduct() {
  const id = $("pr-operator").value;
  const template = $("pr-template").value;
  const area = { network: [], country: [{ type: "country", code: "AT" }], zone: [{ type: "zone", id: "sk", name: "Salzkammergut", stops: ["demo:salzburg-hbf", "demo:fuschl"], ring: SALZKAMMERGUT }] }[$("pr-area").value];
  try {
    await api("POST", "/v1/operator/products", { name: $("pr-name").value, template, params: template === "hours" ? { hours: Number($("pr-hours").value) } : {},
      price: { amount: Math.round(Number($("pr-price").value.replace(",", ".")) * 100), currency: "EUR" }, area, start: template === "hours" || template === "single" ? "purchase" : "chosen" }, keyFor(id));
    $("pr-result").innerHTML = "";
    await reload();
    syncTrust();
  } catch (error) { fail($("pr-result"), error); }
}

// ---- buying ------------------------------------------------------------------------------------------------
function renderCatalog() {
  const stops = STOPS.slice(0, 2);
  $("catalog").innerHTML = state.products.filter((p) => p.sellable).map((p) => `<div class="product" data-product="${esc(p.id)}">
      <header><strong>${esc(pick(p.name))}</strong><span class="price">${money(p.price.amount, p.price.currency)}</span></header>
      <span class="small">${esc(p.operator)}</span>${scopeList(p.description[state.lang])}
      <details data-map="${esc(p.id)}"><summary>${esc(t("map"))}</summary><div class="map"></div></details>
      <div class="options">
        ${p.needs.includes("od") ? `<div class="row"><label class="grow"><span>${esc(t("from"))}</span><select data-f="from">${stops.map((s, i) => `<option value="${i}">${esc(s.name)}</option>`).join("")}</select></label>
          <label class="grow"><span>${esc(t("to"))}</span><select data-f="to">${stops.map((s, i) => `<option value="${i}" ${i === 1 ? "selected" : ""}>${esc(s.name)}</option>`).join("")}</select></label></div>` : ""}
        ${p.needs.includes("holder") ? `<div class="row"><label class="grow"><span>${esc(t("holderName"))}</span><input data-f="name" value="Erika Musterfrau"></label><label><span>${esc(t("birthYear"))}</span><input data-f="born" value="1990" size="5"></label></div>` : ""}
        <label class="check"><input type="checkbox" data-f="live" checked><span>${esc(t("liveOpt"))}</span></label>
        <button class="primary" data-buy="${esc(p.id)}">${esc(t("buy"))}</button><div class="result"></div>
      </div></div>`).join("");
}

async function buy(productId, card) {
  const product = state.products.find((p) => p.id === productId);
  const field = (name) => card.querySelector(`[data-f="${name}"]`);
  const body = { productId };
  let device = null;
  try {
    if (product.needs.includes("od")) {
      const stop = (s) => ({ id: s.stopId, name: s.name, lat: s.lat, lon: s.lon });
      body.od = { from: stop(STOPS[field("from").value]), to: stop(STOPS[field("to").value]) };
    }
    if (product.needs.includes("holder")) body.holder = { name: field("name").value, birthYear: Number(field("born").value) };
    if (field("live").checked) { device = await generateKeyPair(); body.deviceKey = deviceKeyFromJwk(device.publicJwk); }
    const { order } = await api("POST", "/v1/orders", body);
    const { ticket } = await api("POST", `/v1/orders/${order.id}/pay`, { secret: order.secret });
    state.wallet.unshift({ ...ticket, holder: body.holder ? `${body.holder.name}, ${body.holder.birthYear}` : null, deviceKey: device?.privateJwk ?? null });
    saveWallet();
    renderWallet();
    syncTrust();
    $("wallet").scrollIntoView({ behavior: "smooth", block: "start" });
  } catch (error) { fail(card.querySelector(".result"), error); }
}

const shown = async (ticket, at = Math.floor(Date.now() / 1000)) => (ticket.deviceKey ? present(ticket.token, ticket.deviceKey, at) : ticket.token);
function qrSvg(text) {
  const code = qrcode(0, "L");
  code.addData(text, "Byte");
  code.make();
  return code.createSvgTag({ cellSize: 4, margin: 0, scalable: true });
}
async function refreshCodes() {
  for (const el of document.querySelectorAll("[data-qr]")) {
    const ticket = state.wallet.find((x) => x.id === el.dataset.qr);
    if (ticket && typeof qrcode === "function") el.innerHTML = qrSvg(await shown(ticket));
  }
}
function renderWallet() {
  $("wallet").innerHTML = state.wallet.length ? state.wallet.map((x) => `<div class="ticket ${x.status === "revoked" ? "revoked" : ""}">
      <div class="head"><strong>${esc(pick(x.name))}</strong><span>${esc(x.operator)}</span></div>
      <div class="body"><div class="qr" data-qr="${esc(x.id)}"></div>${x.live ? `<div class="live">${esc(t("liveNote"))}</div>` : ""}
        ${scopeList(x.description[state.lang], x.holder)}
        <div class="small">${esc(x.id)} · ${money(x.amount, x.currency)}${x.status === "revoked" ? ` · <span class="chip bad">${esc(t("revoked"))}</span>` : ""}</div>
        <div class="row"><button class="primary" data-show="${esc(x.id)}">${esc(t("show"))}</button>${x.status !== "revoked" && keyFor(x.operatorId) ? `<button data-refund="${esc(x.id)}">${esc(t("refund"))}</button>` : ""}</div>
      </div></div>`).join("") : `<p class="small">${esc(t("walletEmpty"))}</p>`;
  $("check-wallet").innerHTML = state.wallet.map((x) => `<div class="item"><span>${esc(pick(x.name))}<br><span class="small">${esc(x.id)}</span></span>
      <span><button class="ghost" data-use="${esc(x.id)}" data-how="show">${esc(t("useShow"))}</button> ${x.live ? `<button class="ghost" data-use="${esc(x.id)}" data-how="shot">${esc(t("useShot"))}</button> ` : ""}<button class="ghost" data-use="${esc(x.id)}" data-how="forged">${esc(t("useForged"))}</button></span></div>`).join("") || `<p class="small">${esc(t("walletEmpty"))}</p>`;
  const held = $("held").value;
  $("held").innerHTML = `<option value="">${esc(t("noTicket"))}</option>${state.scanned ? `<option value="scan">${esc(t("scanned"))}: ${esc(pick(state.scanned.name))}</option>` : ""}${state.wallet.filter((x) => x.status !== "revoked").map((x) => `<option value="${esc(x.id)}">${esc(t("bought"))}: ${esc(pick(x.name))}</option>`).join("")}`;
  $("held").value = [...$("held").options].some((o) => o.value === held) ? held : state.scanned ? "scan" : "";
  refreshCodes();
}
async function refund(id) {
  const ticket = state.wallet.find((x) => x.id === id);
  try {
    await api("POST", `/v1/operator/tickets/${id}/revoke`, { reason: "refund" }, keyFor(ticket.operatorId));
    ticket.status = "revoked";
    saveWallet();
    renderWallet();
    renderOperatorProducts();
    syncTrust();
  } catch (error) { alertBox(error); }
}
const alertBox = (error) => { $("verdict").className = "verdict invalid"; $("verdict").innerHTML = `<div class="why">${esc(error.message)}</div>`; };

async function showMap(details) {
  const holder = details.querySelector(".map");
  if (holder.dataset.done || typeof L === "undefined") return;
  holder.dataset.done = "1";
  const data = await api("GET", `/v1/products/${encodeURIComponent(details.dataset.map)}/area.geojson`);
  const map = L.map(holder, { scrollWheelZoom: false }).setView([47.8, 13.2], 8);
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 17, attribution: "© OpenStreetMap" }).addTo(map);
  const features = data.features.filter((f) => f.geometry);
  if (features.length) {
    const layer = L.geoJSON({ type: "FeatureCollection", features }, { style: { color: "#1b7a33", weight: 2, fillOpacity: 0.15 } }).addTo(map);
    map.fitBounds(layer.getBounds().pad(0.2));
  }
}

// ---- inspection --------------------------------------------------------------------------------------------
async function syncTrust() {
  try {
    if (!$("offline").checked) {
      const [root, signed] = await Promise.all([api("GET", "/v1/trust/root"), api("GET", "/v1/trust")]);
      localStorage.setItem("ptc-trust", JSON.stringify({ root, signed }));
    }
    const stored = JSON.parse(localStorage.getItem("ptc-trust") ?? "null");
    state.trust = stored ? await openTrustList(stored.signed, stored.root.jwk) : null;
  } catch { /* keep the list we have */ }
  const list = state.trust;
  $("trust-state").textContent = list ? `${t("trustState", list.issuers.length, list.issuers.reduce((n, i) => n + i.keys.length, 0), list.revoked.length, new Date(list.issuedAt * 1000).toLocaleString(state.lang === "de" ? "de-AT" : "en-GB"))}${$("offline").checked ? ` ${t("trustOffline")}` : ""}` : t("trustNone");
  renderOperators();
}

async function check(code) {
  const box = $("verdict");
  if (!state.trust) { box.className = "verdict idle"; box.innerHTML = `<p>${esc(t("trustNone"))}</p>`; return; }
  const stop = STOPS[$("ctx-stop").value] ?? null;
  const context = { operatorId: $("ctx-operator").value, mode: $("ctx-mode").value, ...(stop ? { stop } : {}) };
  const result = await checkTicket(code.trim(), state.trust, { context });
  const word = { valid: t("vValid"), invalid: t("vInvalid"), check: t("vCheck") }[result.level];
  const product = result.product;
  const ticket = result.ticket;
  const words = product && ticket?.nbf ? describeValidity(product.validity, { language: state.lang, operators: state.trust.operators, window: { from: ticket.nbf * 1000, until: ticket.exp * 1000 }, od: ticket.od }) : null;
  box.className = "verdict";
  void box.offsetWidth; // restart the animation
  box.className = `verdict ${result.level}`;
  box.innerHTML = `<div class="big">${esc(word)}</div><div class="why">${esc(VERDICT[state.lang][result.code] ?? result.code)}</div>
    ${product ? `<strong>${esc(pick(product.name))}</strong> <span class="small">${esc(ticket.id)}${ticket.n > 1 ? ` · ${ticket.n} ×` : ""}</span>` : ""}
    ${words ? scopeList(words, ticket.hn ? `${ticket.hn}, ${ticket.hb}` : null) : ""}
    <ul class="checks">${result.checks.map((c) => `<li class="${c.ok ? "" : "no"}">${esc(CHECKS[state.lang][c.name])}${c.detail ? `: ${esc(c.detail)}` : ""}</li>`).join("")}</ul>`;
  // Devices report what they saw once they are online again; the server then notices a ticket used twice.
  if (ticket && !$("offline").checked && keyFor(context.operatorId)) {
    api("POST", "/v1/operator/inspections", { events: [{ ticketId: ticket.id, result: result.level, device: "demo-browser" }] }, keyFor(context.operatorId)).catch(() => {});
  }
}

async function useTicket(id, how) {
  const ticket = state.wallet.find((x) => x.id === id);
  let code = await shown(ticket);
  if (how === "shot") code = await shown(ticket, Math.floor(Date.now() / 1000) - 600);
  if (how === "forged") {
    const parsed = parseTicket(ticket.token);
    code = `PT1.${b64u(encoder.encode(JSON.stringify({ ...parsed.payload, exp: parsed.payload.exp + 86400 })))}.${parsed.signature}`;
  }
  $("code").value = code;
  check(code);
}

let stream = null;
async function camera() {
  const video = $("cam");
  if (stream) { stream.getTracks().forEach((x) => x.stop()); stream = null; video.hidden = true; return; }
  try {
    stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } });
  } catch { $("verdict").className = "verdict idle"; $("verdict").innerHTML = `<p>${esc(t("noCamera"))}</p>`; return; }
  video.srcObject = stream;
  video.hidden = false;
  await video.play();
  const canvas = document.createElement("canvas");
  const detector = "BarcodeDetector" in window ? new BarcodeDetector({ formats: ["qr_code"] }) : null;
  let last = "";
  const tick = async () => {
    if (!stream) return;
    let found = null;
    if (video.videoWidth) {
      if (detector) found = (await detector.detect(video).catch(() => []))[0]?.rawValue ?? null;
      else if (typeof jsQR === "function") {
        canvas.width = video.videoWidth; canvas.height = video.videoHeight;
        const g = canvas.getContext("2d", { willReadFrequently: true });
        g.drawImage(video, 0, 0);
        found = jsQR(g.getImageData(0, 0, canvas.width, canvas.height).data, canvas.width, canvas.height)?.data ?? null;
      }
    }
    if (found && found !== last) { last = found; $("code").value = found; check(found); }
    setTimeout(tick, 250);
  };
  tick();
}

// ---- photo of a ticket -------------------------------------------------------------------------------------
const day = (d) => d.toLocaleDateString("de-AT", { day: "2-digit", month: "2-digit", year: "numeric" });
function samples() {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth() - 2, 1);
  const end = new Date(start.getFullYear() + 1, start.getMonth(), 0);
  const stamped = new Date(now.getTime() - 3600000);
  const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0);
  return [
    { paper: "#e9f3ea", lines: ["KlimaTicket Ö", "Classic", "Erika Musterfrau", `Gültig ab ${day(start)}`, `Gültig bis ${day(end)}`] },
    { paper: "#fdf6e3", lines: ["WIENER LINIEN", "24 Stunden Wien", "Kernzone 100", `Entwertet ${day(stamped)} ${String(stamped.getHours()).padStart(2, "0")}:${String(stamped.getMinutes()).padStart(2, "0")}`] },
    { paper: "#eef1f6", lines: ["Deutschlandticket", "Max Mustermann", `Gültig ab ${day(new Date(now.getFullYear(), now.getMonth(), 1))}`, `Gültig bis ${day(monthEnd)}`] },
  ];
}
function drawSample(sample, canvas) {
  canvas.width = 900; canvas.height = 560;
  const g = canvas.getContext("2d");
  g.fillStyle = sample.paper; g.fillRect(0, 0, 900, 560);
  g.fillStyle = "#111"; g.textBaseline = "top";
  sample.lines.forEach((line, i) => { g.font = `${i === 0 ? "700 72px" : "500 46px"} Arial, Helvetica, sans-serif`; g.fillText(line, 50, i === 0 ? 50 : 100 + i * 82); });
  g.font = "600 26px Arial, Helvetica, sans-serif"; g.fillStyle = "#999"; g.fillText("MUSTER / SAMPLE", 640, 510);
}
function renderSamples() {
  $("samples").innerHTML = "";
  for (const sample of samples()) {
    const button = document.createElement("button");
    const canvas = document.createElement("canvas");
    drawSample(sample, canvas);
    button.append(canvas);
    button.addEventListener("click", () => readPhoto(canvas, sample.lines.join("\n")));
    $("samples").append(button);
  }
}
let ocrScript = null;
async function readPhoto(source, fallback = null) {
  const view = $("photo-view");
  const scale = Math.min(1, 1600 / Math.max(source.width, source.height));
  view.width = Math.round(source.width * scale); view.height = Math.round(source.height * scale);
  const g = view.getContext("2d", { willReadFrequently: true });
  g.drawImage(source, 0, 0, view.width, view.height);
  view.hidden = false;
  state.barcodes = [];
  if (typeof jsQR === "function") {
    const found = jsQR(g.getImageData(0, 0, view.width, view.height).data, view.width, view.height);
    if (found?.data) state.barcodes.push(found.data);
  }
  const status = $("ocr-state");
  status.textContent = t("ocrLoad");
  try {
    ocrScript ??= new Promise((resolve, reject) => {
      const s = document.createElement("script");
      s.src = "https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js";
      s.onload = resolve; s.onerror = reject;
      document.head.append(s);
    });
    await ocrScript;
    const { data } = await Tesseract.recognize(view, "deu+eng", { logger: (m) => { if (m.status === "recognizing text") status.textContent = t("ocrRun", Math.round(m.progress * 100)); } });
    $("ocr-text").value = data.text.trim();
    status.textContent = t("ocrDone");
  } catch {
    ocrScript = null;
    if (fallback) $("ocr-text").value = fallback;
    status.textContent = fallback ? t("ocrFail") : t("ocrFailOwn");
  }
  recogniseTicket();
}
async function recogniseTicket() {
  const out = $("recognised");
  try {
    const result = await api("POST", "/v1/recognize", { text: $("ocr-text").value, barcodes: state.barcodes ?? [] });
    const hit = result.tickets[0] ?? result.candidates[0];
    state.scanned = hit ?? null;
    if (!hit) { out.innerHTML = `<div class="box ask">${esc(t("notRecognised"))}</div>`; renderWallet(); return; }
    const notes = hit.verified ? [t("verifiedCode")] : [hit.assumed.includes("from") ? t("assumedFrom") : null, hit.assumed.includes("until") ? t("assumedUntil") : null].filter(Boolean);
    out.innerHTML = `<div class="box ok"><strong>${esc(pick(hit.name))}</strong> ${hit.verified ? "" : `<span class="chip">${Math.round(hit.confidence * 100)} % ${esc(t("confidence"))}</span>`}
      ${scopeList(hit.description[state.lang])}${notes.map((n) => `<p class="small">${esc(n)}</p>`).join("")}</div>`;
    renderWallet();
    $("held").value = "scan";
    search();
  } catch (error) { fail(out, error); }
}

async function search() {
  const out = $("journeys");
  try {
    const [from, to] = $("route").value.split("|");
    const { journeys } = await api("GET", `/v1/demo/journeys?from=${from}&to=${to}`);
    const held = $("held").value;
    const body = { journeys, ...($("only").checked ? { only: "full" } : {}) };
    if (held === "scan" && state.scanned) body.entitlements = [state.scanned.entitlement];
    else if (held) body.tickets = [state.wallet.find((x) => x.id === held).token];
    const result = await api("POST", "/v1/coverage", body);
    const hasTicket = result.entitlements.length > 0;
    out.innerHTML = result.journeys.map((j) => {
      const c = j.coverage;
      const label = !hasTicket ? "" : c.status === "full" ? `<span class="chip ok">${esc(t("full"))}</span>` : c.status === "none" ? `<span class="chip bad">${esc(t("none"))}</span>`
        : `<span class="chip ask">${esc(c.status === "unknown" ? t("unknown") : t("partial", c.missing))}</span>`;
      return `<div class="journey ${hasTicket ? c.status : ""}"><header><strong>${clock(j.startTime)} – ${clock(j.endTime)}</strong><span class="small">${Math.round(j.duration / 60)} ${esc(t("min"))}</span>
        <span>${label}${c.extra ? ` <span class="chip">${esc(t("extra"))} ${money(c.extra.amount, c.extra.currency)}</span>` : ""}${c.approximate && hasTicket ? ` <span class="chip">${esc(t("approx"))}</span>` : ""}</span></header>
        ${j.legs.map((leg, i) => {
    const l = c.legs[i];
    const badge = !l.needsTicket ? "" : !hasTicket ? "" : `<span class="chip ${l.covered === true ? "ok" : l.covered === null ? "ask" : "bad"}">${esc(l.text[state.lang])}</span>`;
    return `<div class="leg"><span>${clock(leg.startTime)}<br><span class="sub">${clock(leg.endTime)}</span></span>
            <span><span class="line">${esc(leg.routeShortName ?? t("walk"))}</span> ${esc(leg.agencyName ?? "")}<br><span class="sub">${esc(leg.from.name)} → ${esc(leg.to.name)}</span></span>${badge}
            ${l.offer ? `<span class="offer">${esc(t("addOn"))}: ${esc(pick(l.offer.name))} (${esc(l.offer.operator)}), ${money(l.offer.price.amount, l.offer.price.currency)}</span>` : ""}</div>`;
  }).join("")}</div>`;
    }).join("") || `<div class="box ask">${esc(t("nothingFull"))}</div>`;
  } catch (error) { fail(out, error); }
}

// ---- API page ----------------------------------------------------------------------------------------------
const API = [
  ["GET", "/v1/products", "Katalog: jedes Ticket mit Geltungsbereich in Daten und in Worten", "Catalogue: every ticket with its scope in data and in words"],
  ["POST", "/v1/orders", "Bestellung anlegen, danach /v1/orders/{id}/pay", "Create an order, then /v1/orders/{id}/pay"],
  ["GET", "/v1/trust", "Signierte Vertrauensliste für Prüfgeräte (Schlüssel, Geltungsbereiche, Sperrliste)", "Signed trust list for checking devices (keys, scopes, revocations)"],
  ["POST", "/v1/validate", "Online-Prüfung eines Codes, dieselbe Logik wie offline", "Online check of a code, same logic as offline"],
  ["POST", "/v1/recognize", "Text und Barcode eines fotografierten Tickets → erkanntes Ticket", "Text and barcode of a photographed ticket → recognised ticket"],
  ["POST", "/v1/coverage", "Verbindungen (MOTIS-Format) gegen vorhandene Tickets prüfen und filtern", "Check and filter connections (MOTIS format) against tickets held"],
  ["POST", "/v1/operators/apply", "Betreiber meldet sich an", "An operator applies"],
  ["POST", "/v1/operator/products", "Ticket aus Vorlage anlegen oder neue Version veröffentlichen", "Create a ticket from a template or publish a new version"],
  ["POST", "/v1/operator/import/gtfs-fares", "Tarife aus GTFS-Fares v2 als Entwürfe übernehmen", "Import fares from GTFS-Fares v2 as drafts"],
  ["POST", "/v1/operator/tickets/{id}/revoke", "Erstattung: Ticket kommt auf die Sperrliste", "Refund: the ticket goes on the revocation list"],
  ["GET", "/v1/operator/statement", "Abrechnung: Umsatz, Provision, Auszahlung", "Statement: sales, commission, payout"],
];
function renderApi() {
  $("api-list").innerHTML = API.map((r) => `<div class="api-row"><div><span class="m">${r[0]}</span> <code>${esc(r[1])}</code></div><div class="small">${esc(r[state.lang === "de" ? 2 : 3])}</div></div>`).join("")
    + `<details><summary>curl</summary><pre>curl ${esc(location.origin)}/v1/products?sellable=1\n\ncurl -X POST ${esc(location.origin)}/v1/recognize \\\n  -H 'content-type: application/json' \\\n  -d '{"text":"KlimaTicket Ö gültig bis 28.02.2027"}'</pre></details>`;
}

function renderAll() {
  renderOperators();
  renderCatalog();
  renderWallet();
  renderSamples();
  renderApi();
  const names = Object.fromEntries((state.demo?.places ?? []).map((p) => [p.id, p.name]));
  const route = $("route").value;
  $("route").innerHTML = ROUTES.map(([a, b]) => `<option value="${a}|${b}">${esc(names[a] ?? a)} → ${esc(names[b] ?? b)}</option>`).join("");
  if (route) $("route").value = route;
}

// ---- wiring ------------------------------------------------------------------------------------------------
document.addEventListener("click", (event) => {
  const el = event.target.closest("[data-tab],[data-go],[data-approve],[data-retire],[data-buy],[data-show],[data-refund],[data-use]");
  if (!el) return;
  const d = el.dataset;
  if (d.tab || d.go) go(d.tab ?? d.go);
  else if (d.approve) approve(d.approve);
  else if (d.retire) api("POST", `/v1/operator/products/${d.retire}/retire`, {}, keyFor($("pr-operator").value)).then(reload).catch(alertBox);
  else if (d.buy) buy(d.buy, el.closest(".product"));
  else if (d.show) { go("check"); useTicket(d.show, "show"); }
  else if (d.refund) refund(d.refund);
  else if (d.use) useTicket(d.use, d.how);
});
document.addEventListener("toggle", (event) => { if (event.target.dataset?.map && event.target.open) showMap(event.target).catch(() => {}); }, true);
$("lang").addEventListener("click", () => { state.lang = state.lang === "de" ? "en" : "de"; localStorage.setItem("ptc-lang", state.lang); applyLanguage(); });
$("op-apply").addEventListener("click", applyOperator);
$("pr-save").addEventListener("click", saveProduct);
$("pr-operator").addEventListener("change", renderOperatorProducts);
$("pr-template").addEventListener("change", () => { $("pr-hours-wrap").hidden = $("pr-template").value !== "hours"; });
$("trust-sync").addEventListener("click", syncTrust);
$("offline").addEventListener("change", syncTrust);
$("code-check").addEventListener("click", () => check($("code").value));
$("cam-start").addEventListener("click", camera);
$("recognise").addEventListener("click", recogniseTicket);
$("search").addEventListener("click", search);
$("only").addEventListener("change", search);
$("held").addEventListener("change", search);
$("route").addEventListener("change", search);
$("photo").addEventListener("change", async (event) => {
  const file = event.target.files[0];
  if (!file) return;
  const image = await createImageBitmap(file);
  readPhoto(image);
});
setInterval(refreshCodes, 10000);

applyLanguage();
go(location.hash.slice(1) && $(location.hash.slice(1)) ? location.hash.slice(1) : "overview");
reload().then(syncTrust).catch((error) => fail($("op-result"), error));

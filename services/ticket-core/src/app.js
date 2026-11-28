// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// The HTTP API. `createApp` returns a fetch-style handler (Request → Response), so it runs under Node
// (src/node.js), in tests without a socket, and on a Workers-style host.
//
// Public (no key):
//   GET  /v1/operators                    directory with onboarding state
//   GET  /v1/templates                    ticket templates an operator can pick from
//   GET  /v1/products[?operator=&q=&sellable=1]   catalogue, each with its scope in data and in words
//   GET  /v1/products/{id}                one product      GET /v1/products/{id}/area.geojson   scope for a map
//   POST /v1/orders                       { productId, start?, travellers?, od?, holder?, deviceKey? }
//   POST /v1/orders/{id}/pay              { secret }  → the signed ticket (demo payment)
//   GET  /v1/orders/{id}?secret=          order and ticket again
//   GET  /v1/trust                        signed trust list for checking devices     GET /v1/trust/root   root key
//   POST /v1/validate                     { code, context? }  online check, same logic as the offline one
//   POST /v1/recognize                    { text, barcodes? }  which ticket is this
//   POST /v1/coverage                     { tickets?, entitlements?, journeys, only? }  which rides are covered
//   POST /v1/operators/apply              an operator applies → API key (shown once)
// Operator (Authorization: Bearer <API key>):
//   GET  /v1/operator                     own record       POST /v1/operator/keys        key change
//   GET/POST /v1/operator/products        list / create or new version
//   POST /v1/operator/products/{id}/publish | /retire
//   POST /v1/operator/import/gtfs-fares   { files }  drafts from the operator's fare feed
//   POST /v1/operator/tickets/{id}/revoke refund       POST /v1/operator/inspections   reports from devices
//   GET  /v1/operator/statement           sales, commission, payout
// Publit (Authorization: Bearer <ADMIN_TOKEN>):
//   GET  /v1/admin/operators              every operator with its check format (never the secret)
//   POST /v1/admin/operators              add an operator directly, already approved → API key
//   POST /v1/admin/operators/{id}/approve | /suspend
//   GET  /v1/admin/formats                the check formats Publit can issue
//   POST /v1/admin/operators/{id}/format  { type, config, secret }  how this operator's tickets are coded
//   POST /v1/admin/operators/{id}/format/test   a sample code to hold under the operator's device
//   POST /v1/admin/verify                 { code }  did Publit issue this code, and is it still good
// Demo only (DEMO=on):
//   GET  /v1/demo   keys for the demo console      GET /v1/demo/journeys?from=&to=     POST /v1/demo/reset

import { timingSafeEqual } from "node:crypto";
import { ApiError, applyOperator, approveOperator, operatorForKey, publicOperator, rotateKey, setStatus } from "./operators.js";
import { TEMPLATES, areaGeoJson, currentVersion, findVersion, productView, publishProduct, retireProduct, saveProduct } from "./products.js";
import { createOrder, issueTicket, recordInspections, revokeTicket, statement } from "./orders.js";
import { rootKey, signedTrustList, trustList } from "./trust.js";
import { recognise } from "./recognize.js";
import { importGtfsFares } from "./gtfsfares.js";
import { FORMATS, formatView, hashCode, issueCode, setFormat, verifyCode } from "./formats.js";
import { vaultKey } from "./vault.js";
import { parseTicket, verifyTicketSignature } from "./core/token.js";
import { checkTicket } from "./core/validate.js";
import { coverJourney, coverLeg, needsTicket, routerModes, sameStop } from "./core/coverage.js";
import { describeValidity, reasonText } from "./core/describe.js";
import { resolveWindow } from "./core/time.js";
import { PLACES, demoJourneys, seed } from "./demo/seed.js";

const CORS = { "access-control-allow-origin": "*", "access-control-allow-headers": "content-type, authorization", "access-control-allow-methods": "GET, POST, OPTIONS" };

function json(body, status = 200, extra = {}) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...CORS, ...extra } });
}

function bearer(request) {
  const header = request.headers.get("authorization") ?? "";
  return header.startsWith("Bearer ") ? header.slice(7).trim() : null;
}

function same(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && timingSafeEqual(x, y);
}

export function createApp({ store, env = {}, now = () => Date.now(), fetch = globalThis.fetch }) {
  const demo = env.DEMO === "on";
  const secretsKey = vaultKey(env.SECRETS_KEY);
  let ready = null;
  const prepare = async () => {
    await rootKey(store, env);
    if (demo && !store.data.demo) await seed(store, now());
  };

  const operatorList = () => Object.values(store.data.operators);

  function describe(version, extra = {}) {
    const options = { operators: operatorList(), ...extra };
    return { de: describeValidity(version.validity, { ...options, language: "de" }), en: describeValidity(version.validity, { ...options, language: "en" }) };
  }

  function productOut(product, version = currentVersion(product)) {
    return { ...productView(product, version), operator: store.data.operators[product.operatorId]?.name ?? product.operatorId,
      description: describe(version), ...(version.review ? { review: version.review } : {}) };
  }

  function ticketOut(ticket) {
    const { version } = findVersion(store, ticket.productId, ticket.version);
    return {
      id: ticket.id, token: ticket.token, status: ticket.status, productId: ticket.productId, version: ticket.version,
      name: version.name, operatorId: ticket.operatorId, operator: store.data.operators[ticket.operatorId].name,
      validFrom: new Date(ticket.validFrom).toISOString(), validUntil: new Date(ticket.validUntil).toISOString(),
      amount: ticket.amount, currency: ticket.currency, live: ticket.live, od: ticket.od,
      // What the operator's checking device reads. For Publit's own format that is the token itself.
      format: ticket.format ?? "publit", code: ticket.code ?? ticket.token, codeEncoding: ticket.codeEncoding ?? "text", symbology: ticket.symbology ?? "qr",
      description: describe(version, { window: { from: ticket.validFrom, until: ticket.validUntil }, od: ticket.od }),
    };
  }

  function requireOperator(request) {
    const operator = operatorForKey(store, bearer(request));
    if (!operator) throw new ApiError(401, "unauthorized", "a valid operator API key is needed");
    return operator;
  }

  function requireActive(request) {
    const operator = requireOperator(request);
    if (operator.status !== "active") throw new ApiError(403, "not_active", "this operator has not been approved yet");
    return operator;
  }

  function requireAdmin(request) {
    const token = bearer(request);
    if (!env.ADMIN_TOKEN || !token || !same(token, env.ADMIN_TOKEN)) throw new ApiError(401, "unauthorized", "the admin token is needed");
  }

  // Publit's word for a code: it is in the ledger exactly as issued, carries what the operator's format
  // demands, has not been refunded and is within its time. Works for every format, also for codes only the
  // operator's own system can read.
  function guarantee(code) {
    const text = typeof code === "string" ? code.trim() : "";
    const checks = [];
    let ticket = null;
    if (text.startsWith("PT1.")) {
      const parsed = parseTicket(text.split("~")[0]);
      ticket = (parsed && store.data.tickets[parsed.payload.id]) ?? null;
      if (ticket && ticket.token !== text.split("~")[0]) ticket = null;
    } else if (text) ticket = store.data.tickets[(store.data.codes ?? {})[hashCode(text)]] ?? null;
    checks.push({ name: "ledger", ok: Boolean(ticket), code: ticket ? "issued_by_publit" : "not_issued" });
    if (!ticket) return { level: "invalid", code: "not_issued", checks, ticket: null };
    const format = ticket.code ? verifyCode(store.data.operators[ticket.operatorId], ticket, secretsKey) : true;
    checks.push({ name: "format", ok: format !== false, code: format === true ? "format_ok" : format === null ? "format_operator" : "format_bad" });
    const revoked = ticket.status === "revoked";
    checks.push({ name: "revocation", ok: !revoked, code: revoked ? "revoked" : "not_revoked" });
    const time = now() < ticket.validFrom - 30000 ? "not_yet_valid" : now() > ticket.validUntil + 30000 ? "expired" : "in_time";
    checks.push({ name: "time", ok: time === "in_time", code: time });
    const reason = format === false ? "format_bad" : revoked ? "revoked" : time !== "in_time" ? time : "issued";
    return { level: reason === "issued" ? "valid" : "invalid", code: reason, checks, ticket };
  }

  // Tickets someone holds, from signed codes or from a recognised photo, as the coverage engine wants them.
  async function entitlementsFrom(body) {
    const list = [];
    const problems = [];
    for (const code of (Array.isArray(body.tickets) ? body.tickets : []).slice(0, 10)) {
      const parsed = parseTicket(typeof code === "string" ? code.split("~")[0] : "");
      const operator = parsed && store.data.operators[parsed.payload.iss];
      const key = operator?.keys.find((k) => k.kid === parsed.payload.kid && k.status !== "compromised");
      const found = parsed && findVersion(store, parsed.payload.p, parsed.payload.pv);
      if (!key || !found || !(await verifyTicketSignature(parsed, key.jwk))) { problems.push({ ticket: list.length + problems.length, code: "not_valid" }); continue; }
      if (store.data.revoked[parsed.payload.id]) { problems.push({ ticket: list.length + problems.length, code: "revoked" }); continue; }
      list.push({ source: "ticket", verified: true, productId: parsed.payload.p, version: parsed.payload.pv, name: found.version.name,
        validFrom: parsed.payload.nbf * 1000, validUntil: parsed.payload.exp * 1000, validity: found.version.validity, od: parsed.payload.od ?? null });
    }
    for (const item of (Array.isArray(body.entitlements) ? body.entitlements : []).slice(0, 10)) {
      const product = store.data.products[item?.productId];
      const version = product && (product.versions.find((v) => v.version === item.version) ?? currentVersion(product));
      const from = typeof item?.validFrom === "number" ? item.validFrom : Date.parse(item?.validFrom);
      const until = typeof item?.validUntil === "number" ? item.validUntil : Date.parse(item?.validUntil);
      if (!version || !Number.isFinite(from) || !Number.isFinite(until)) { problems.push({ entitlement: item?.productId ?? null, code: "not_valid" }); continue; }
      list.push({ source: item.source === "manual" ? "manual" : "scan", verified: false, productId: product.id, version: version.version,
        name: version.name, validFrom: from, validUntil: until, validity: version.validity, od: item.od ?? null });
    }
    return { list, problems };
  }

  // The cheapest product on sale that would cover a ride nobody's ticket covers.
  function offerFor(leg, context) {
    let best = null;
    const start = Date.parse(leg.startTime);
    for (const product of Object.values(store.data.products)) {
      const version = currentVersion(product);
      if (!product.sellable || version?.status !== "published" || store.data.operators[product.operatorId].status !== "active") continue;
      const window = resolveWindow(version.validity.time, start, version.validity.timeZone);
      const od = { from: leg.from, to: leg.to };
      const fixed = version.validity.area.find((r) => r.type === "route");
      const onRoute = Boolean(fixed) && sameStop(leg.from, fixed.from ?? leg.from) && sameStop(leg.to, fixed.to ?? leg.to);
      const fits = coverLeg(leg, { validFrom: window.from, validUntil: window.until, validity: version.validity, od }, context, onRoute).covered === true;
      if (fits && (!best || version.price.amount < best.price.amount)) {
        best = { productId: product.id, name: version.name, operator: store.data.operators[product.operatorId].name, price: version.price,
          ...(version.needs.includes("od") ? { od: { from: { id: leg.from.stopId, name: leg.from.name }, to: { id: leg.to.stopId, name: leg.to.name } } } : {}) };
      }
    }
    return best;
  }

  async function route(request, url) {
    const path = url.pathname.replace(/\/+$/, "") || "/";
    const method = request.method;
    const body = method === "POST" ? await request.json().catch(() => { throw new ApiError(400, "invalid", "the body must be JSON"); }) : null;
    if (body !== null && (typeof body !== "object" || Array.isArray(body))) throw new ApiError(400, "invalid", "the body must be a JSON object");
    let m;

    if (method === "GET" && path === "/health") return json({ ok: true, demo });

    // ---- catalogue -------------------------------------------------------------------------------------
    if (method === "GET" && path === "/v1/operators") return json({ operators: operatorList().map(publicOperator) });
    if (method === "GET" && path === "/v1/templates") return json({ templates: TEMPLATES.map((t) => ({ id: t.id, name: t.name, params: t.params })) });
    if (method === "GET" && path === "/v1/products") {
      const q = (url.searchParams.get("q") ?? "").toLowerCase();
      const operator = url.searchParams.get("operator");
      const sellable = url.searchParams.get("sellable");
      const products = Object.values(store.data.products)
        .filter((p) => currentVersion(p)?.status === "published" && (!operator || p.operatorId === operator) && (!sellable || p.sellable === (sellable === "1")))
        .map((p) => productOut(p))
        .filter((p) => !q || `${p.name.de} ${p.name.en} ${p.operator}`.toLowerCase().includes(q));
      return json({ products });
    }
    if (method === "GET" && (m = /^\/v1\/products\/([^/]+)(\/area\.geojson)?$/.exec(path))) {
      const product = store.data.products[decodeURIComponent(m[1])];
      const version = product && currentVersion(product);
      if (!version || version.status !== "published") throw new ApiError(404, "not_found", "no such product");
      return m[2] ? json(areaGeoJson(version.validity)) : json({ product: productOut(product, version) });
    }

    // ---- buying ----------------------------------------------------------------------------------------
    if (method === "POST" && path === "/v1/orders") {
      const order = createOrder(store, body, now());
      return json({ order: { id: order.id, secret: order.secret, status: order.status, amount: order.amount, currency: order.currency },
        payment: { kind: "demo", pay: `/v1/orders/${order.id}/pay` } }, 201);
    }
    if ((m = /^\/v1\/orders\/([A-Z0-9]+)(\/pay)?$/.exec(path))) {
      const order = store.data.orders[m[1]];
      const secret = method === "POST" ? body.secret : url.searchParams.get("secret");
      if (!order || typeof secret !== "string" || !same(secret, order.secret)) throw new ApiError(404, "not_found", "no such order");
      if (method === "POST" && m[2]) {
        if (env.DEMO_PAYMENTS !== "on" && !demo) throw new ApiError(503, "no_payment", "no payment provider is configured");
        const ticket = await issueTicket(store, order, now(), { key: secretsKey, fetch });
        return json({ order: { id: order.id, status: order.status }, ticket: ticketOut(ticket) });
      }
      if (method === "GET" && !m[2]) {
        return json({ order: { id: order.id, status: order.status, amount: order.amount, currency: order.currency },
          ticket: order.ticketId ? ticketOut(store.data.tickets[order.ticketId]) : null });
      }
    }

    // ---- checking --------------------------------------------------------------------------------------
    if (method === "GET" && path === "/v1/trust") return json(await signedTrustList(store, env, now()), 200, { "cache-control": "public, max-age=60" });
    if (method === "GET" && path === "/v1/trust/root") {
      const root = await rootKey(store, env);
      return json({ kid: root.kid, jwk: root.publicJwk });
    }
    if (method === "POST" && path === "/v1/validate" && typeof body.code === "string" && !body.code.trim().startsWith("PT1.")) {
      // A code in an operator's own format. On board the operator's device decides; this is Publit's record.
      const result = guarantee(body.code);
      const found = result.ticket && findVersion(store, result.ticket.productId, result.ticket.version);
      return json({ level: result.level, code: result.code, checks: result.checks, ledger: true, ticketId: result.ticket?.id ?? null, format: result.ticket?.format ?? null,
        operator: result.ticket ? store.data.operators[result.ticket.operatorId].name : null, name: found?.version.name ?? null,
        description: found ? describe(found.version, { window: { from: result.ticket.validFrom, until: result.ticket.validUntil }, od: result.ticket.od }) : null });
    }
    if (method === "POST" && path === "/v1/validate") {
      const result = await checkTicket(body.code, trustList(store, now()), { now: now(), context: body.context ?? null });
      const found = result.ticket && findVersion(store, result.ticket.p, result.ticket.pv);
      return json({ ...result, entitlement: undefined, product: undefined,
        name: found?.version.name ?? null,
        description: found && result.ticket.nbf ? describe(found.version, { window: { from: result.ticket.nbf * 1000, until: result.ticket.exp * 1000 }, od: result.ticket.od }) : null });
    }

    // ---- "I already have a ticket" ----------------------------------------------------------------------
    if (method === "POST" && path === "/v1/recognize") {
      if (typeof (body.text ?? "") !== "string" || (body.text ?? "").length > 20000) throw new ApiError(400, "invalid", "text is too long");
      const result = await recognise(store, { text: body.text ?? "", barcodes: Array.isArray(body.barcodes) ? body.barcodes : [] }, now());
      for (const item of [...result.tickets, ...result.candidates]) {
        const found = findVersion(store, item.productId, item.entitlement.version);
        item.description = describe(found.version, { window: { from: item.entitlement.validFrom, until: item.entitlement.validUntil }, od: item.entitlement.od });
        item.entitlement.validFrom = new Date(item.entitlement.validFrom).toISOString();
        item.entitlement.validUntil = new Date(item.entitlement.validUntil).toISOString();
      }
      return json(result);
    }
    if (method === "POST" && path === "/v1/coverage") {
      if (!Array.isArray(body.journeys) || body.journeys.length > 50) throw new ApiError(400, "invalid", "journeys must be a list of at most 50");
      const { list, problems } = await entitlementsFrom(body);
      const context = { operators: operatorList() };
      let journeys = body.journeys.map((journey, index) => {
        if (!journey || !Array.isArray(journey.legs) || journey.legs.length > 40) throw new ApiError(400, "invalid", "every journey needs legs");
        const coverage = coverJourney(journey, list, context);
        coverage.legs = coverage.legs.map((leg) => ({
          ...leg, text: { de: reasonText(leg, "de"), en: reasonText(leg, "en") },
          ...(leg.needsTicket && leg.covered !== true && body.offers !== false ? { offer: offerFor(journey.legs[leg.index], context) } : {}),
        }));
        const offers = coverage.legs.map((l) => l.offer).filter(Boolean);
        coverage.missing = coverage.legs.filter((l) => l.needsTicket && l.covered !== true).length;
        coverage.extra = offers.length && offers.length === coverage.missing && new Set(offers.map((o) => o.price.currency)).size === 1
          ? { amount: [...new Map(offers.map((o) => [o.productId + JSON.stringify(o.od ?? ""), o])).values()].reduce((sum, o) => sum + o.price.amount, 0), currency: offers[0].price.currency } : null;
        return { index, ...journey, coverage };
      });
      if (body.only === "full") journeys = journeys.filter((j) => j.coverage.status === "full");
      else {
        const rank = { full: 0, unknown: 1, partial: 2, none: 3 };
        journeys = journeys.map((j, i) => [j, i]).sort((a, b) => rank[a[0].coverage.status] - rank[b[0].coverage.status] || a[1] - b[1]).map(([j]) => j);
      }
      return json({
        entitlements: list.map((e) => ({ source: e.source, verified: e.verified, productId: e.productId, version: e.version, name: e.name,
          validFrom: new Date(e.validFrom).toISOString(), validUntil: new Date(e.validUntil).toISOString(), approximate: Boolean(e.validity.approximate),
          routerModes: routerModes(e.validity) })),
        problems, journeys,
      });
    }

    // ---- operators -------------------------------------------------------------------------------------
    if (method === "POST" && path === "/v1/operators/apply") {
      const { operator, apiKey } = applyOperator(store, { ...body, demo: false }, now());
      return json({ operator: publicOperator(operator), apiKey, next: "Publit checks the company and switches the operator to active." }, 201);
    }
    if ((m = /^\/v1\/admin\/operators\/([a-z0-9-]+)\/(approve|suspend)$/.exec(path)) && method === "POST") {
      requireAdmin(request);
      const operator = m[2] === "approve" ? await approveOperator(store, m[1], now()) : setStatus(store, m[1], "suspended");
      return json({ operator: publicOperator(operator) });
    }
    if (path === "/v1/admin/operators") {
      requireAdmin(request);
      if (method === "GET") {
        const sold = {};
        for (const ticket of Object.values(store.data.tickets)) sold[ticket.operatorId] = (sold[ticket.operatorId] ?? 0) + 1;
        return json({ operators: operatorList().map((o) => ({ ...publicOperator(o), contact: o.contact, commissionBps: o.commissionBps, format: formatView(o), tickets: sold[o.id] ?? 0 })) });
      }
      if (method === "POST") {
        const { operator, apiKey } = applyOperator(store, { ...body, demo: false }, now());
        await approveOperator(store, operator.id, now());
        if (body.format) await setFormat(store, operator, body.format, { key: secretsKey, now: now() });
        if (demo) { store.data.demo.operatorKeys[operator.id] = apiKey; store.save(); }
        return json({ operator: { ...publicOperator(operator), format: formatView(operator) }, apiKey }, 201);
      }
    }
    if (path === "/v1/admin/formats" && method === "GET") {
      requireAdmin(request);
      return json({ formats: FORMATS, placeholders: ["id", "product", "operator", "from", "until", "fromIso", "untilIso", "n", "class"], secretsReady: Boolean(secretsKey) });
    }
    if ((m = /^\/v1\/admin\/operators\/([a-z0-9-]+)\/format(\/test)?$/.exec(path)) && method === "POST") {
      requireAdmin(request);
      const operator = store.data.operators[m[1]];
      if (!operator) throw new ApiError(404, "not_found", "no such operator");
      if (!m[2]) {
        await setFormat(store, operator, body, { key: secretsKey, now: now() });
        return json({ operator: { ...publicOperator(operator), format: formatView(operator) } });
      }
      if (!operator.format) throw new ApiError(409, "publit_format", "this operator uses Publit's own code; buy a demo ticket to see one");
      const sample = { id: "TEST0000001", productId: `${operator.id}.test`, operatorId: operator.id, name: "Testticket", validFrom: now(), validUntil: now() + 3600000,
        travellers: 1, class: 2, od: null, holder: null, issuedAt: now(), price: null, test: true };
      const issued = await issueCode(operator, sample, { key: secretsKey, fetch });
      return json({ test: true, format: operator.format.type, ...issued, check: verifyCode(operator, { format: operator.format.type, code: issued.code }, secretsKey) });
    }
    if (path === "/v1/admin/verify" && method === "POST") {
      requireAdmin(request);
      const result = guarantee(body.code);
      const ticket = result.ticket;
      const found = ticket && findVersion(store, ticket.productId, ticket.version);
      return json({ guaranteed: result.level === "valid", code: result.code, checks: result.checks,
        ticket: ticket ? { id: ticket.id, orderId: ticket.orderId, operatorId: ticket.operatorId, operator: store.data.operators[ticket.operatorId].name, productId: ticket.productId,
          name: found.version.name, format: ticket.format ?? "publit", reference: ticket.reference ?? null, status: ticket.status, issuedAt: new Date(ticket.issuedAt).toISOString(),
          validFrom: new Date(ticket.validFrom).toISOString(), validUntil: new Date(ticket.validUntil).toISOString(), amount: ticket.amount, currency: ticket.currency } : null });
    }
    if (path === "/v1/operator" && method === "GET") {
      const operator = requireOperator(request);
      return json({ operator: { ...publicOperator(operator), legalName: operator.legalName, contact: operator.contact, company: operator.company, commissionBps: operator.commissionBps } });
    }
    if (path === "/v1/operator/keys" && method === "POST") {
      const operator = await rotateKey(store, requireActive(request), body, now());
      return json({ operator: publicOperator(operator) });
    }
    if (path === "/v1/operator/products") {
      if (method === "GET") {
        const operator = requireOperator(request);
        return json({ products: Object.values(store.data.products).filter((p) => p.operatorId === operator.id)
          .map((p) => ({ ...productOut(p, p.versions.at(-1)), versions: p.versions.map((v) => ({ version: v.version, status: v.status, hash: v.hash, publishedAt: v.publishedAt })) })) });
      }
      if (method === "POST") {
        const { product, version } = await saveProduct(store, requireActive(request), { ...body, sellable: true, approximate: false, review: undefined }, now());
        return json({ product: productOut(product, version) }, 201);
      }
    }
    if ((m = /^\/v1\/operator\/products\/([a-z0-9.-]+)\/(publish|retire)$/.exec(path)) && method === "POST") {
      const operator = requireActive(request);
      if (m[2] === "retire") { retireProduct(store, operator, m[1]); return json({ ok: true }); }
      const { product, version } = publishProduct(store, operator, m[1], now());
      return json({ product: productOut(product, version) });
    }
    if (path === "/v1/operator/import/gtfs-fares" && method === "POST") {
      return json({ drafts: await importGtfsFares(store, requireActive(request), body.files, now()) }, 201);
    }
    if ((m = /^\/v1\/operator\/tickets\/([A-Z0-9]+)\/revoke$/.exec(path)) && method === "POST") {
      const ticket = revokeTicket(store, requireActive(request), m[1], body.reason, now());
      return json({ ticket: { id: ticket.id, status: ticket.status } });
    }
    if (path === "/v1/operator/inspections" && method === "POST") {
      return json({ results: recordInspections(store, requireActive(request), body.events, now()) });
    }
    if (path === "/v1/operator/statement" && method === "GET") return json(statement(store, requireOperator(request)));

    // ---- demo ------------------------------------------------------------------------------------------
    if (demo && path === "/v1/demo" && method === "GET") {
      return json({ adminToken: env.ADMIN_TOKEN ?? null, operatorKeys: store.data.demo.operatorKeys, places: PLACES, note: "Demo data. No real tickets, no real contracts." });
    }
    if (demo && path === "/v1/demo/journeys" && method === "GET") {
      const time = url.searchParams.get("time");
      return json({ journeys: demoJourneys(url.searchParams.get("from"), url.searchParams.get("to"), time ? Date.parse(time) : now()) });
    }
    if (demo && path === "/v1/demo/remember-key" && method === "POST") {
      // The demo console keeps the key of an operator it has just onboarded, so the next visitor can go on.
      const operator = operatorForKey(store, body.apiKey);
      if (operator) { store.data.demo.operatorKeys[operator.id] = body.apiKey; store.save(); }
      return json({ ok: Boolean(operator) });
    }
    if (demo && path === "/v1/demo/reset" && method === "POST") {
      const root = store.data.root;
      store.reset();
      store.data.root = root;
      await seed(store, now());
      return json({ ok: true });
    }
    throw new ApiError(404, "not_found", "no such endpoint");
  }

  return async function handle(request) {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    try {
      ready ??= prepare();
      await ready;
      return await route(request, new URL(request.url));
    } catch (error) {
      if (error instanceof ApiError) return json({ error: error.code, message: error.message }, error.status);
      console.error(error);
      return json({ error: "internal", message: "something went wrong" }, 500);
    }
  };
}

export { needsTicket };

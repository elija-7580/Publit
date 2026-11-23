// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Demo payments: stands in for Stripe so the whole purchase can be tried without a Stripe account.
// Only with DEMO_PAYMENTS="on", no Stripe key and no real seller key (so nothing real is ever booked unpaid).
// Orders live in memory for an hour; a restart forgets them. The page says clearly that nothing is charged.

const TTL = 60 * 60 * 1000;

export function demoPaymentsActive(env) {
  return env.DEMO_PAYMENTS === "on" && !env.STRIPE_SECRET_KEY && !env.DISTRIBUSION_API_KEY && env.DEMO_PROVIDER === "on";
}

function id(prefix) {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return prefix + Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function demoPayments(now = () => Date.now()) {
  const sessions = new Map();
  const prune = () => { for (const [k, s] of sessions) if (now() - s.created > TTL) sessions.delete(k); };
  const byIntent = (intentId) => [...sessions.values()].find((s) => s.payment_intent.id === intentId);

  return {
    async createCheckout(params) {
      prune();
      const sessionId = id("cs_demo_");
      const amount = (params.line_items ?? []).reduce((sum, i) => sum + (i.price_data?.unit_amount ?? 0) * (i.quantity ?? 1), 0);
      const origin = new URL(params.success_url).origin;
      sessions.set(sessionId, {
        id: sessionId, created: now(), amount, currency: params.line_items?.[0]?.price_data?.currency ?? "eur",
        lines: (params.line_items ?? []).map((i) => ({ name: i.price_data?.product_data?.name ?? "", amount: i.price_data?.unit_amount ?? 0 })),
        success_url: params.success_url.replace("{CHECKOUT_SESSION_ID}", sessionId), cancel_url: params.cancel_url,
        url: `${origin}/v1/demo-pay?session=${sessionId}`,
        payment_intent: { id: id("pi_demo_"), status: "requires_payment_method", metadata: { ...(params.payment_intent_data?.metadata ?? {}) } },
      });
      const s = sessions.get(sessionId);
      return { id: s.id, url: s.url };
    },
    async session(sessionId) {
      const s = sessions.get(sessionId);
      return s ? { id: s.id, payment_intent: { ...s.payment_intent, metadata: { ...s.payment_intent.metadata } } } : null;
    },
    async setMetadata(intentId, values) {
      const s = byIntent(intentId);
      if (s) Object.assign(s.payment_intent.metadata, values);
    },
    async capture(intentId, amount) {
      const s = byIntent(intentId);
      if (s) { s.payment_intent.status = "succeeded"; s.captured = amount; }
    },
    async cancel(intentId) {
      const s = byIntent(intentId);
      if (s) s.payment_intent.status = "canceled";
    },
    /** The demo payment page: GET shows it, POST pays or cancels. */
    async page(request) {
      const url = new URL(request.url);
      const s = sessions.get(url.searchParams.get("session") ?? "");
      if (!s) return new Response("Unknown or expired order", { status: 404 });
      if (request.method === "POST") {
        const form = new URLSearchParams(await request.text());
        if (form.get("action") === "pay" && s.payment_intent.status === "requires_payment_method") {
          s.payment_intent.status = "requires_capture";
          return Response.redirect(s.success_url, 303);
        }
        return Response.redirect(s.cancel_url, 303);
      }
      const money = (c) => `${(c / 100).toFixed(2).replace(".", ",")} ${s.currency.toUpperCase()}`;
      const esc = (t) => String(t).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
      const rows = s.lines.map((l) => `<tr><td>${esc(l.name)}</td><td class="r">${money(l.amount)}</td></tr>`).join("");
      const html = `<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Publit Demo-Zahlung</title><style>
body{font:17px -apple-system,system-ui,sans-serif;margin:0;padding:24px;background:#f5f5f7;color:#111}
@media(prefers-color-scheme:dark){body{background:#111;color:#eee}.card{background:#1c1c1e!important}}
.card{background:#fff;border-radius:16px;padding:20px;max-width:480px;margin:0 auto}
.warn{background:#ffc531;color:#111;border-radius:10px;padding:10px 12px;font-weight:600;margin-bottom:16px}
table{width:100%;border-collapse:collapse}td{padding:6px 0;vertical-align:top}.r{text-align:right;white-space:nowrap;padding-left:12px}
.total td{border-top:1px solid #8884;font-weight:700;padding-top:10px}
button{width:100%;font-size:17px;padding:14px;border-radius:12px;border:0;margin-top:12px}
.pay{background:#111;color:#fff}.cancel{background:#8882;color:inherit}
@media(prefers-color-scheme:dark){.pay{background:#fff;color:#111}}
</style></head><body><div class="card">
<div class="warn">Demo: Es wird nichts abgebucht, die Tickets sind nicht gültig.</div>
<table>${rows}<tr class="total"><td>Gesamt</td><td class="r">${money(s.amount)}</td></tr></table>
<form method="post"><button class="pay" name="action" value="pay">Bezahlen (Demo)</button>
<button class="cancel" name="action" value="cancel">Abbrechen</button></form></div></body></html>`;
      return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" } });
    },
  };
}

<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich -->

# Publit ticket shop

Optional. Lets people buy tickets for a whole route inside Publit: one offer per leg from whichever seller sells
it, **one payment** for all legs, then the tickets go straight into the app's Tickets tab. Legs no seller covers
keep the operator's own ticket link.

The seller API keys and the Stripe key stay on this Cloudflare Worker, never in the app. Nothing is stored or
logged here: offers travel as signed tokens, and the order lives in the Stripe payment's metadata.

## How a purchase works

1. `POST /v1/offers` – the app sends the route's transit legs (places, times, mode, operator). Each active seller
   that covers a leg is asked for a matching connection; the first offer wins. Each offer comes back as a signed
   token (30 minutes), so the app cannot change seller, trip or price.
2. `POST /v1/checkout` – the app sends the chosen tokens, the ticket holder's name and e-mail, and that the terms
   were accepted. Every leg is reserved with its seller; if one fails, the others are released. Then one Stripe
   Checkout page is created for all legs, with **manual capture**: the money is only authorised.
3. The customer pays on Stripe's page (card, Apple Pay, Google Pay, …). Stripe returns to `GET /v1/return`, which
   redirects to `publit://shop/return?order=…`.
4. `POST /v1/orders/{order}/complete` – every reservation is confirmed with its seller, then **only the booked legs
   are captured**. A leg that fails is released and not charged. If nothing could be booked, the authorisation is
   cancelled. The tickets (PDF and/or code) are returned. Calling it again returns the tickets again without
   charging twice. If the app never calls it, the authorisation lapses and the customer is not charged.

## Sellers

| Seller | Covers | Status | Switched on by |
| --- | --- | --- | --- |
| [Distribusion](https://docs.distribusion.com/dt/api) | Intercity bus, many railways, ferries, airport transfers | Implemented after the public API docs; test with the demo key | `DISTRIBUSION_API_KEY` |
| Demo | Every transit leg, made-up price | For testing only; tickets say "DEMO – not a valid ticket" | `DEMO_PROVIDER = "on"` (never with live Stripe keys) |

Planned, each needs a contract and API access first: Wiener Linien ticket interface (Vienna single, 24 h, 7 day
tickets), Samtrafiken Connect / BoB (Sweden), railways via OSDM, transport authorities using Masabi Justride.
To add one, write a provider object as described in `src/providers/index.js` and list it there.

## Open ticket-link layer (for any app)

The cheap first step: no customer money and no personal data. An app sends the operators of a journey and the
ticket links it already has; it gets back the best link per leg, sent through the shop's affiliate program when
there is one. Works without Stripe or seller keys (only `PARTNER_TEMPLATES` for Publit's own programs).

```sh
curl -X POST https://<worker>/v1/links -H 'Content-Type: application/json' -d '{
  "legs": [{ "index": 0, "operator": "FlixBus", "links": { "booking": "https://shop.flixbus.de/search?…" } },
           { "index": 1, "operator": "ÖBB" }],
  "partners": { "flixbus": "https://www.awin1.com/cread.php?awinmid=<advertiser>&awinaffid=<your id>&ued={url}" }
}'
```

- `links` per leg: `booking`, `fares`, `website` (first valid one wins); without any, a known shop for the operator.
- `partners` (optional, "bring your own ID"): your own tracking links per program (`db`, `flixbus`, `trainline`,
  `omio`, `sncf`, `eurostar`). They must be https on the network's own host (Awin, Partnerize, Impact,
  Tradedoubler) and contain `{url}` once. Legs without your ID use Publit's, which funds this service.
- Answer: `{ links: [{ leg, operator, url, source, partner, via: "caller" | "publit" | null }] }`. CORS is open.
- `GET /v1/partners` lists Publit's active programs. The Publit app loads it on start, so a new partner program
  goes live by changing `PARTNER_TEMPLATES` in `wrangler.toml` and redeploying, without an app update.

## Setup

1. Stripe: create an account, get the secret key (`sk_test_…` first). Apple Pay on Checkout needs the domain of
   this worker registered in Stripe (Settings → Payment methods → Apple Pay).
2. Distribusion: ask partner@distribusion.com for a demo API key. The default base URL is the demo environment;
   set `DISTRIBUSION_BASE_URL = "https://api.distribusion.com/retailers/v4"` in `wrangler.toml` for production.
3. Deploy:
   ```sh
   npm install
   openssl rand -hex 32 | npx wrangler secret put TOKEN_SECRET
   npx wrangler secret put STRIPE_SECRET_KEY
   npx wrangler secret put DISTRIBUSION_API_KEY
   npm run deploy
   ```
4. Build the app with the build setting `TICKET_SHOP_URL` set to the worker's address (Info.plist key
   `PublitTicketShopURL`). Without it the app shows no "Buy tickets in Publit".

## On your own server (without Cloudflare)

The same code runs with Node 20 or newer; `src/node.js` replaces the Cloudflare runtime and keeps the rate limit
in memory. No `npm install` is needed: the shop has no dependencies.

```sh
git clone https://github.com/elija-7580/Publit.git && cd Publit/services/ticket-shop
cat > .env <<'ENV'
TOKEN_SECRET=<openssl rand -hex 32>
STRIPE_SECRET_KEY=sk_test_…
DEMO_PROVIDER=on
PORT=8787
ENV
chmod 600 .env
node --env-file=.env src/node.js
```

To try it without any Stripe account, leave out `STRIPE_SECRET_KEY` and set `DEMO_PAYMENTS=on` together with
`DEMO_PROVIDER=on`: a demo payment page (`/v1/demo-pay`) stands in for Stripe and charges nothing. It switches
itself off as soon as a Stripe key or a real seller key is set.

It listens on 127.0.0.1 only. Put a reverse proxy with HTTPS in front, for example Caddy:

```
shop.example.org {
    reverse_proxy 127.0.0.1:8787
}
```

To keep it running, a systemd unit with `WorkingDirectory=…/services/ticket-shop`,
`ExecStart=/usr/bin/node --env-file=.env src/node.js` and `Restart=always` is enough. Optional variables:
`DISTRIBUSION_API_KEY`, `DISTRIBUSION_BASE_URL`, `RATE_LIMIT` (requests per minute per IP, default 30), `HOST`.

Before selling for real: a company, the sellers' contracts, terms and a privacy notice for the shop, and
customer support for refunds and delays. Distribusion invoices ticket price minus commission monthly
(`execute_payment=false`, payment method `demand_note`).

## Test

```sh
node --test
```

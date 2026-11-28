<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich -->

# Publit ticket core

A prototype of the platform behind "every operator's ticket in one app". It answers four questions:

1. **How does an operator join?** It applies, Publit checks the company, and it creates its tickets from
   templates. An operator without a sales system needs nothing else; one with a system keeps it.
2. **How does a conductor know a ticket is real?** The ticket is a signed QR code. Checking devices load one
   signed trust list (all issuers' public keys, every product's scope, revoked tickets) and then check offline.
3. **Where and from when is a ticket valid?** The scope is data, written once by the operator. The sentence the
   customer reads, the map, the conductor's verdict and the connection search are all generated from it.
4. **What about a ticket someone already has?** A photo is enough: the text is read on the phone, matched to a
   known ticket, and the connection search marks which rides it covers.

Everything here is a prototype with demo data. No real tickets are sold and no operator has a contract.

## Try it

```sh
cd services/ticket-core
npm run demo            # http://127.0.0.1:8790, Node 20+, no dependencies
npm test
```

The demo console has four pages: bring an operator on board, buy a ticket, check it like a conductor (also
offline, with an old screenshot, with a forged code), and scan a ticket to filter connections. German and English.

## How it fits together

```
operator ──apply──▶ operators.js ──approve──▶ signing key
operator ──template + area + price──▶ products.js ──▶ immutable version + hash of its scope
buyer ──order, pay──▶ orders.js ──▶ signed ticket  PT1.<payload>.<signature>
checking device ◀── trust.js: signed list of keys, scopes, revocations ──▶ core/validate.js (offline)
app ──text read from a photo──▶ recognize.js ──▶ ticket + period ──▶ core/coverage.js ◀── journeys from the router
```

`src/core` has no server code in it: the browser loads the same files, so the conductor's check and the
server's check cannot disagree.

### Operators (`src/operators.js`)

Every operator known from timetable data is in the directory as `listed`. Joining the sale has four levels:

| Level | For whom | What Publit does |
| --- | --- | --- |
| `link` | anyone, no contract | links to the operator's own shop |
| `hosted` | operators without a sales system | issues and signs the tickets with a key kept for that operator |
| `own-keys` | operators that issue tickets themselves | only lists their public key, so their tickets pass the same check |
| `api` | operators with a sales system (OSDM, Distribusion, own API) | sells through an adapter, hands over the operator's original ticket |

States: `listed` → `pending` → `active` → `suspended`. The API key is shown once; only its hash is stored.
A key change keeps old tickets valid; marking a key as stolen voids every ticket signed with it.

### Scope of a ticket (`src/core/coverage.js`)

```json
{ "timeZone": "Europe/Vienna",
  "time": { "type": "duration", "minutes": 1440 },
  "operators": "any",
  "area": [{ "type": "zone", "id": "100", "name": "Wien", "stops": ["…"], "ring": [[16.18, 48.17], "…"] }],
  "modes": { "except": ["COACH"] },
  "except": [{ "operators": ["cat"], "label": { "de": "City Airport Train", "en": "City Airport Train" } }],
  "rides": "unlimited", "class": 2, "personal": false }
```

- `time`: `duration`, `calendar` (day, month, year, optional late end) or `fixed`. At purchase it becomes two
  timestamps in the ticket.
- `area`: every stop of a ride must satisfy one rule: `country`, `zone` (stop list and/or outline), `stops`,
  or `route` (between two stops, fixed or chosen at purchase).
- A published version never changes. The ticket carries the version number and the hash of this object.
- Results are `covered: true | false | null` with a reason, and `certainty: exact | approximate`. Approximate
  means a rough outline decided, or the issuer has not confirmed the model (tickets we only recognise).

Templates: `single`, `single_route`, `hours`, `day`, `week`, `month`, `year`. GTFS-Fares v2 feeds are imported
as drafts (`src/gtfsfares.js`); what the feed does not say is listed for the operator to confirm.

### The ticket code (`src/core/token.js`)

`PT1.<base64url JSON>.<ECDSA P-256 signature>`, about 350 characters. With a device key in the payload the code
must be shown live: the buyer's phone appends the time and its own signature every few seconds, so a
screenshot is refused after a minute. This follows the design of UIC rail barcodes (signed, with a dynamic
part) and Sweden's BoB tickets, but it is this prototype's own envelope. For railways the production path is
to issue real UIC barcodes with the same content so existing scanners read them.

### Checking (`src/core/validate.js`)

Issuer and key known, signature, product and scope hash, revocation, live proof, time, and, when the device
knows where it is, the scope. Verdict `valid`, `check` (needs a human: ID, unknown operator) or `invalid`.

### The operator's own check format (`src/formats.js`, `src/vault.js`)

Every operator already has checking software, and it only accepts codes in its own format. So the code a
ticket shows is set per operator, by Publit only (admin token):

| Format | The conductor's device sees | What Publit needs from the operator |
| --- | --- | --- |
| `publit` | Publit's signed code (PT1) | nothing; checked with the web check |
| `operator-api` | the operator's original code, issued by its own sales system when the ticket is paid | API address and access token |
| `shared-secret` | a text with a keyed checksum (HMAC) in the operator's layout | the secret and the layout |
| `uic-918-3` | the Aztec code of European rail tickets (`#UT`, U_HEAD + U_TLAY, DSA signature) | its company code; it adds Publit's public key to its key list, or hands over a signing key |

Secrets are stored encrypted (AES-256-GCM, key from `SECRETS_KEY`, never in the data file) and no endpoint
returns them. `POST /v1/admin/operators/{id}/format/test` gives a sample code to hold under a real device
before anything is sold. Whatever the format, Publit keeps its own signed record of every ticket, so
`POST /v1/admin/verify` answers for any code: issued by Publit exactly like this, fits the operator's format,
not refunded, within its time.

The UIC 918.3 output is read back by an independent open-source decoder (npm `uic-918-3`, checked by hand,
not a dependency). Whether a given operator's devices accept it depends on that operator: its key list, and
which records it expects (many use U_FLEX or their own records today). That has to be tried with each one.

### A ticket someone already holds (`src/recognize.js`, `POST /v1/coverage`)

The app sends the text and barcodes it read. Our own code is verified and exact; other tickets are matched by
their printed words, tolerant of OCR mistakes, and the period is taken from the printed dates plus the
product's time rule. `POST /v1/coverage` takes journeys in MOTIS itinerary format (what the Publit apps
already have) and returns each ride as covered or not with the reason, `only: "full"` filters, and rides
nobody's ticket covers get the cheapest product on sale as an offer.

## API

All JSON. CORS is open. The full list with bodies is at the top of `src/app.js`.

| | |
| --- | --- |
| `GET /v1/products`, `/v1/products/{id}`, `/v1/products/{id}/area.geojson` | catalogue with scope in data and in German and English words |
| `POST /v1/orders` → `POST /v1/orders/{id}/pay` | buy; returns the signed ticket |
| `GET /v1/trust`, `GET /v1/trust/root` | trust list for checking devices |
| `POST /v1/validate` | online check |
| `POST /v1/recognize`, `POST /v1/coverage` | recognise a ticket, check journeys against tickets |
| `POST /v1/operators/apply` | an operator applies |
| `/v1/operator/…` (Bearer API key) | products, publish, retire, GTFS import, key change, refunds, inspections, statement |
| `/v1/admin/operators/{id}/approve`, `/suspend` (Bearer `ADMIN_TOKEN`) | Publit's side of onboarding |
| `GET/POST /v1/admin/operators`, `GET /v1/admin/formats` | all operators with their format; add one directly |
| `POST /v1/admin/operators/{id}/format`, `…/format/test` | set an operator's check format and key; sample code |
| `POST /v1/admin/verify` | did Publit issue this code, and is it still good |

## What is not built

- Real payment. `pay` is a demo step; `services/ticket-shop` has the Stripe checkout this would plug into.
- Adapters for OSDM and Distribusion (`operator-api` is a plain JSON call), UIC U_FLEX / dynamic barcodes, VDV-KA.
- Acceptance tests on real checking devices: no operator has tried a code from here yet.
- A database and a key service: state is one JSON file, hosted private keys lie in it.
- Splitting a ride at a border or zone edge (today a ride is covered whole or not).
- Legal: selling long-distance tickets needs a travel agency licence in Austria; contracts with operators.

## Configuration

`DEMO=on` loads demo data and opens `/v1/demo` (never in production), `DATA_FILE`, `ADMIN_TOKEN`,
`ROOT_KEY_JWK`, `SECRETS_KEY`, `PORT`, `HOST`, `RATE_LIMIT`. See `src/node.js`.

`PRIVATE=on` closes the whole service, pages included, to anyone without `ADMIN_TOKEN` (Bearer token, or the
password when the browser asks). Use it wherever real operator keys are stored.

The demo console loads five libraries from jsDelivr: qrcode-generator (MIT), jsQR (Apache-2.0), Leaflet
(BSD-2-Clause), tesseract.js (Apache-2.0) and bwip-js (MIT, for Aztec codes). Map tiles © OpenStreetMap contributors.

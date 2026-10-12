# Publit pass signer

Optional. Signs the manifest of Apple Wallet passes that Publit builds on the device, so the Pass Type ID
private key never ships in the app. Receives only `pass.json` and `manifest.json` (base64) and returns the
detached PKCS #7 signature. No ticket document, image or personal data beyond what is on the pass is sent,
and nothing is stored or logged by this code.

Checks before signing:

- `passTypeIdentifier` and `teamIdentifier` match this deployment
- only known pass file names, each with a SHA-1 hash; `pass.json` hash matches; `icon.png` present
- no `webServiceURL` / `authenticationToken` (passes cannot be updated remotely)
- size limits; 20 requests per minute per IP (Cloudflare rate limiting)

## Setup

1. Apple Developer Program → Certificates, Identifiers & Profiles → Identifiers → Pass Type IDs → create
   `pass.io.github.publit.ticket` (or your own) → create its certificate and export it with the key as `.p12`.
2. Convert:
   ```sh
   openssl pkcs12 -in pass.p12 -clcerts -nokeys -out pass-cert.pem
   openssl pkcs12 -in pass.p12 -nocerts -nodes -out pass-key.pem
   curl -O https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer
   openssl x509 -inform der -in AppleWWDRCAG4.cer -out wwdr.pem
   ```
3. Set `PASS_TYPE_ID` and `TEAM_ID` in `wrangler.toml`, then:
   ```sh
   npm install
   npx wrangler secret put PASS_CERT_PEM < pass-cert.pem
   npx wrangler secret put PASS_KEY_PEM < pass-key.pem
   npx wrangler secret put WWDR_CERT_PEM < wwdr.pem
   npm run deploy
   ```
4. Add `PublitPassTypeIdentifier`, `PublitTeamIdentifier` and `PublitPassSignerURL` (…/sign) to the app's
   Info.plist (see docs/tickets.md).

Delete the local `.p12` and `.pem` files afterwards; never commit them.

## Test

```sh
npm install
npm test
```

The tests create a throwaway CA and certificate, sign a manifest and check the signature with OpenSSL when it is
installed. CI does not run them yet (workflow changes need a maintainer); add a step like the AMTAB worker's.

# Tickets as passes

Status: built and tested, **not wired into the app**. Nothing here is reachable from the app's UI.
The first ticket version (`TicketStore`, `TicketsView`) stays switched off with `Features.tickets = false`.

The idea follows apps like NeatPass: your ticket arrives as a PDF, photo or screenshot; Publit reads it on the
iPhone, you check the result, and you get a clean pass with the code ready for the gate. Publit's own take: it stays
inside a transit app, so a pass can belong to a saved trip, and passes valid at the trip's time show up there.

## Flow

1. **Add** (`PassImportView`): photo or screenshot (PhotosPicker), PDF or image file (file importer, 25 MB limit),
   or scan a paper ticket (VisionKit document camera). Multi-page PDFs ask for the page.
2. **Read on the device** (`TicketRecognizer`): Vision finds QR, Aztec, PDF417 and Code 128 codes and the text.
   PDFs use their embedded text when there is enough of it. The page's main colour is offered as "From ticket".
   Nothing is uploaded.
3. **Understand** (`TicketTextParser`, platform-independent): operator, product (Deutschlandticket, KlimaTicket,
   Sparschiene, …), type, route, validity (labels in German, English, French and Italian; birth and purchase dates
   are ignored), passenger, class, price, ticket number. The issuer of a UIC 918.3 rail code (`#UT…`) is read
   from the code header. Fields stay empty when nothing supports them.
4. **Check** (`PassEditorView`): live preview of the pass; every field editable; choose among several codes or
   none; colour (presets, operator colour, colour from the ticket) and symbol.
5. **Use** (`PassWalletView`, `PassDetailView`): passes grouped as valid now, upcoming, no dates, expired
   (folded). The pass card shows operator, title, validity badge, route, details, a perforation and the code.
   Tapping the code opens it full screen on white; brightness goes to 100 % while a code is shown and comes
   back when it leaves the screen or the app goes to the background. "Show original" opens the PDF (PDFKit)
   or image (pinch and double-tap zoom).
6. **Apple Wallet (optional)** (`AddToWalletButton`, `WalletPassBuilder`): see below.

Codes that change every few seconds (many operator apps) cannot be copied. Publit says so on the import and check
screens, and every pass says that only the operator's ticket is valid.

## Files

| Part | File | Runs on |
| --- | --- | --- |
| Model, validity, grouping | `Sources/Tickets/TicketPass.swift` | iOS, Linux |
| Colours with WCAG AA text and labels | `Sources/Tickets/PassStyle.swift` | iOS, Linux |
| Text rules, known operators | `Sources/Tickets/TicketTextParser.swift` | iOS, Linux |
| Store, documents, legacy import | `Sources/Tickets/PassStore.swift` | iOS, Linux |
| pass.json, manifest, package, signer client | `Sources/Tickets/WalletPass.swift`, `Sources/Util/SHA1.swift`, `Sources/Util/ZipWriter.swift` | iOS, Linux |
| Vision and PDF reading | `Sources/Tickets/TicketRecognizer.swift` | iOS |
| Drawing codes again | `Sources/Tickets/BarcodeRenderer.swift` | iOS |
| Screens | `Sources/Tickets/Views/*` | iOS |
| Demo data for screenshots | `Sources/Tickets/PassSamples.swift` (DEBUG only) | iOS |
| Signing service | `services/pass-signer` | Cloudflare Workers |

Codes are stored with their text, raw bytes when the text does not carry them (binary rail codes), and the
archived `CIBarcodeDescriptor`, so the exact scanned symbol can be drawn again.

Tests: `Tests/TicketPassTests.swift` (parser, validity, styles, SHA-1, CRC-32, ZIP, pass.json, store) and
`testF12TicketPassScreens` in the UI tests (screenshots `pass-*.png` in the `ci-results` branch).

## Apple Wallet

Wallet only accepts passes signed with a Pass Type ID certificate (paid Apple Developer Program). The private key
must not ship in an open-source app, so `services/pass-signer` holds it. The app sends only pass.json and
manifest.json (no document, no image of the ticket); the service checks Pass Type ID, Team ID, file names and the
pass.json hash, refuses web-service fields, and returns the detached signature. Export is hidden until these
Info.plist keys are set:

| Key | Example |
| --- | --- |
| `PublitPassTypeIdentifier` | `pass.io.github.publit.ticket` |
| `PublitTeamIdentifier` | your 10-character Team ID |
| `PublitPassSignerURL` | `https://publit-pass-signer.<account>.workers.dev/sign` (HTTPS only) |

Wallet passes are `sharingProhibited` and have no web service, so they are never updated remotely.

## Wiring it in (when the design is approved)

- [ ] Inject a `PassStore` in `PublitApp` and run `importLegacy` once for existing tickets.
- [ ] Replace `TicketsView` in Settings with `PassWalletView`; route ticket deep links to `PassDetailView`.
- [ ] Trip screens: show `passes(forTrip:at:)` with a "Show ticket" button that opens the pass or the code directly.
- [ ] Live Activity and Siri "Show ticket" with the new store.
- [ ] Share extension: "Share to Publit" from Mail and the Files app.
- [ ] Remove `TicketStore`, `TicketsView`, `TicketCard`, `Features.tickets` after the migration release.
- [ ] Test on a device: recognition of real tickets (ÖBB, DB, Deutschlandticket, KlimaTicket, Wiener Linien),
      gate scanners with the redrawn codes, brightness, VoiceOver, large text.
- [ ] Wallet: Apple Developer Program, Pass Type ID, deploy the signer, add the Info.plist keys, test on a device.

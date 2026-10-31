# Publit iOS – Funktionen und Screens (vollständige Übersicht)

> Stand: Version 0.1.0 (Build 64). Diese Datei beschreibt **jede Funktion und jeden Screen** der iOS-App, der Apple-Watch-App, der Widgets/Live Activity, der Share-Extension und der Siri-Kurzbefehle.
> **Pflege:** Jede Änderung an `Sources/`, `Watch/`, `Widgets/` oder `Share/` muss diese Datei im selben Commit/PR mitändern (siehe Abschnitt „Aktualisierung“ ganz unten). Die maschinell erzeugte Liste aller Views steht in [`FUNKTIONEN-INVENTAR.md`](FUNKTIONEN-INVENTAR.md) und wird von der CI automatisch aktualisiert.

## Inhalt

1. [Grundprinzipien](#1-grundprinzipien)
2. [App-Start, Onboarding, Navigation](#2-app-start-onboarding-navigation)
3. [Tab „In der Nähe“ (Nearby)](#3-tab-in-der-nähe-nearby)
4. [Abfahrtstafel einer Haltestelle](#4-abfahrtstafel-einer-haltestelle)
5. [Linien, Linien-Detail und Fahrplan](#5-linien-linien-detail-und-fahrplan)
6. [Fahrt eines Fahrzeugs (TripView)](#6-fahrt-eines-fahrzeugs-tripview)
7. [Stationskarte / Karte](#7-stationskarte--karte)
8. [Tab „Planen“ (Plan)](#8-tab-planen-plan)
9. [Ortssuche](#9-ortssuche)
10. [Routenoptionen](#10-routenoptionen)
11. [Smart Routing](#11-smart-routing)
12. [Routendetail (Itinerary)](#12-routendetail-itinerary)
13. [Gespeicherte Fahrt, Fahrt starten, Live-Fahrt (Guide)](#13-gespeicherte-fahrt-fahrt-starten-live-fahrt-guide)
14. [Tab „Tickets“](#14-tab-tickets)
15. [Tab „Gespeichert“ (Saved)](#15-tab-gespeichert-saved)
16. [Einstellungen](#16-einstellungen)
17. [Benachrichtigungen](#17-benachrichtigungen)
18. [Widgets und Live Activity](#18-widgets-und-live-activity)
19. [Siri / Kurzbefehle (App Intents)](#19-siri--kurzbefehle-app-intents)
20. [Share-Extension und Deep Links](#20-share-extension-und-deep-links)
21. [Apple Watch](#21-apple-watch)
22. [iPad / breites Layout](#22-ipad--breites-layout)
23. [Datenquellen, Abdeckung, Offline](#23-datenquellen-abdeckung-offline)
24. [Datenschutz, Diagnose, Datenexport](#24-datenschutz-diagnose-datenexport)
25. [Gemeinsame UI-Bausteine](#25-gemeinsame-ui-bausteine)
26. [Nur für Entwicklung/Tests](#26-nur-für-entwicklungtests)
27. [Aktualisierung dieser Datei](#27-aktualisierung-dieser-datei)

---

## 1. Grundprinzipien

- Kostenlos, Open Source (MIT), **kein Konto, keine Werbung, kein Tracking**. Alle gespeicherten Orte, Fahrten, Tickets bleiben auf dem Gerät (JSON-Dateien in Application Support, Tickets mit Dateischutz „complete“).
- Routing und Abfahrten über **Transitous** (MOTIS 2 API, GTFS + GTFS-RT/SIRI), mit identifizierendem User-Agent und sichtbarer Quellenangabe (`AttributionFooter`). Ausfallserver: MOTIS-Europa-Server (`ServerFailover`).
- Zusätzliche Live-Quellen (optional): ÖBB, Wiener Linien, search.ch, deutsche HAFAS-Server, ACTV Venedig, SL Stockholm, TfL London (siehe §23).
- Optional Google Places (Suche) und Google Maps SDK (Karte), nur mit API-Key.
- Standort wird nur bei einer Suche mitgeschickt und auf ~1 m (Routing) bzw. ~1 km (Such-Bias) gerundet.
- Unterstützt: iOS 17+, watchOS 10+, Hell/Dunkel, Dynamic Type inkl. Accessibility-Größen (gestapeltes Layout), VoiceOver-Texte („live, 3 minutes late“, „timetable time, no live data“ …), iPad-Layout.
- Sprachen über String Catalogs (`Localizable.xcstrings`, `InfoPlist.xcstrings`, `AppShortcuts.xcstrings`, `Transfers.xcstrings`).
- Akku-Schonung (`Energy`): im Stromsparmodus oder bei Hitze aktualisieren Live-Screens halb so oft.

## 2. App-Start, Onboarding, Navigation

### Launch-Splash (`LaunchSplash`)
Animiertes Logo, mindestens 0,7 s, höchstens 2 s; endet früher, sobald die erste Abfahrtstafel geladen ist.

### Onboarding (`OnboardingView`, nur beim ersten Start, Vollbild, Seiten mit Punkten, „Skip“)
1. **„Public transport, without the noise.“** – Abfahrten in der Nähe, Routen durch Europa, Begleitung bis zum Aussteigen; kein Konto, keine Werbung, kein Tracking.
2. **„Departures where you are“** – Erklärung der Standortnutzung (nur mit Suche gesendet, nie gespeichert). Buttons „Allow location“ / „Not now“.
3. **„Home and Work“** – Zuhause und Arbeit festlegen (Felder „Not set“ → Ortssuche); später unter „Gespeichert“ änderbar.
4. **„On the way“** – Erklärung Live-Fahrt, Umstiege, Aussteige-Hinweis, Sperrbildschirm, Widget. Button „Get started“.
Ohne Onboarding startet die Standortabfrage sofort.

### Tab-Leiste (`RootView`, `AdaptiveTabs` ab iOS 18)
| Tab | Symbol | Inhalt |
|---|---|---|
| Nearby | location.circle | Abfahrten / Linien in der Nähe |
| Plan | calendar | Routenplaner |
| Tickets | ticket | Ticket-Wallet |
| Saved | star | Gespeicherte Orte, Linien, Fahrten |

- Start-Tab einstellbar (Einstellungen → „Start screen“: Nearby oder Plan).
- **Live-Leiste** (`LiveTripBar`) über der Tab-Leiste, sobald eine Fahrt läuft oder bald startet (siehe §13).
- Globale Overlays: geteiltes Ticket-Dokument → Import-Sheet; Deep Link Fahrt → Vollbild (bei laufender Fahrt nur mit „Minimize“ schließbar, kein Wegwischen); Ticket-Links → Ticket-Sheet; geteilte Route → `SharedRouteView`; Haltestellen-Link → Abfahrtstafel.
- Beim Start: alte Offline-Kopien (> 7 Tage) gelöscht; Tickets der ersten Ticket-Version werden einmalig zu Passes migriert; Watch-Sync startet; Siri-Kurzbefehl-Parameter (gespeicherte Haltestellen) aktualisiert; Hintergrundaufgabe für Linienstörungen registriert.

## 3. Tab „In der Nähe“ (Nearby) – `NearbyView`

- **Umschalter** „Departures“ / „Lines“ (Picker „View“).
- **Abfahrten**: nächste Haltestellen/Stationen, gruppiert pro Station bzw. pro Straßen-Haltestelle (Seite der Straße), mit `StopGroupHeader` (Name, Entfernung, Hauptziele). Suchradius stufenweise **500 m → 1,5 km → 5 km**, bis Abfahrten gefunden werden; weit entfernte Stopps werden mit Distanz und Gehzeit angezeigt statt „keine Abfahrten“.
- Pro Zeile (`DepartureRow`): Linien-Badge (Betreiberfarbe, Verkehrsmittel-Symbol), „Towards …“ (Fahrtrichtung, bei Ringlinien das Ausstiegsziel + „Circle line“), Gleis/Steig, Uhrzeit + Countdown („now“, „x min“), Verspätung „+x min“, Live/Fahrplan-Kennzeichnung, „Cancelled“, „Rail replacement bus“ (SEV).
- **Linien-Gruppierung** (`LineAtStopRow`): pro Linie die nächsten Abfahrten je Richtung („U3 → Moosach: 3, 13, 23 min“).
- **Verkehrsmittel-Filter** (`ModeFilterBar`): All, Train, S-Bahn, Metro, Tram, Bus, Ferry, Other. Leerer Filter = alle. Bei leerem Ergebnis: „No departures for these modes“ + „Show all modes“.
- **„Where to now? Route from your location“** – Sprung in den Planer ab aktuellem Standort; **„Next trip: …“** wenn eine gespeicherte Fahrt ansteht; Abschnitt **„Active trip“** bei laufender Fahrt.
- **Störungen** (Abschnitt „Alerts“, `ServiceAlertsView`): nach Schwere sortiert, dedupliziert, aufklappbar.
- **Abdeckungswarnung** (`CoverageBanner`) „Not reliable here“, wenn der Standort in einem Gebiet mit fehlenden Daten liegt.
- Toolbar: „Station map“ (Karte), Einstellungen (Zahnrad).
- Zustände: „Location is off“ (Hinweis, Planen geht trotzdem), „Departures unavailable“, „No departures nearby“ („No departures within 5 km …“ + Button Stationskarte), „Couldn't refresh. Times may be out of date.“, Offline-Hinweis „Offline. Showing data from HH:MM.“
- Pull-to-Refresh, automatische Aktualisierung im Vordergrund.

## 4. Abfahrtstafel einer Haltestelle – `StopDeparturesView`

- Geöffnet aus Nearby, Karte, Gespeichert, Widget, Siri, Deep Link `publit://stop/…`.
- Alle Abfahrten der Station oder einer einzelnen Straßen-Haltestelle, mit Filter, Störungen, Abdeckungshinweis, „No upcoming departures.“
- Aktionen: **„Route here“**, **„Route from here“**, **„Save“** (Haltestelle speichern), **„Share departures“**, Linie speichern („Save line“ / „Saved line“).
- Tippen auf Abfahrt → Fahrt des Fahrzeugs (§6).

## 5. Linien, Linien-Detail und Fahrplan – `LinesView`, `LineDetailView`, `LineTimetableView`

- **Linienliste**: Linien im Umkreis, je mit nächster Haltestelle („At …“), sortiert nach Verkehrsmittel (Zug zuerst) und natürlicher Nummer („2“ vor „10“); Abschnitt „Saved lines“.
- **Suche** „Line, destination or station“ (Liniennummer exakt, dann Präfix, dann Ziele; unabhängig von Leerzeichen/Akzenten) plus Abschnitt „Stations“.
- Leere Zustände: kein Standort, „No lines found nearby.“, „No lines for these modes.“, „No line nearby matches. Try a station below.“
- **Linien-Detail**: Richtungswahl („Direction“, „Towards …“), Karte des Linienverlaufs (`LineMap`) mit **geschätzten Fahrzeugpositionen** aus Live-Zeiten („Vehicle positions are estimated from live departure times.“), Haltestellenliste („x stops“, „Tap a stop for its timetable.“), Linie speichern.
- **Fahrplan einer Haltestelle** (`LineTimetableView`): Tagwahl („Day“), Richtung, alle Abfahrten des Tages („x departures“), Hinweis „Scheduled times. Live delays are on the departure board.“, „No departures on this day.“

## 6. Fahrt eines Fahrzeugs (`TripView`, `LineDeparturesView`)

- Alle Halte der Fahrt mit Plan-/Live-Zeit, Verspätung „+x“, Gleis „Pl. x“, bereits passierte Halte.
- Karte (`TripMap`) mit **geschätzter Fahrzeugposition** („Estimated vehicle position“), Status „Not departed yet“, „Between A and B“, „At …“, „Arrived at …“; ohne Live-Daten aus dem Fahrplan geschätzt.
- Aktionen pro Halt: „Route here“, „Route from here“; „From … to here“; Linie speichern.
- Liste weiterer Abfahrten derselben Linie.

## 7. Stationskarte / Karte – `StationMapView`

- Vollbildkarte mit Stationen (gebündelte Bahnsteige; beim Hineinzoomen < ~1,5 km einzelne Straßen-Haltestellen; max. einige hundert Pins), „My location“, „Search this area“, „Zoom in to see stations / lines and vehicles“.
- **Suche** „Search places, sights and stops“ und **„Find nearby“**-Kategorien wie Apple Maps (Restaurants, Apotheken, Ladestationen …, farbcodiert) → „All … in this area“ / „No places found“.
- **Ebenen** (`MapLayersSheet`, „Map layers“): Kartenstil (Standard, Transit/gedämpft, Satellite, Satellite ohne Namen), 3D-Gelände und Gebäude, Places of interest, Traffic, Lines, Vehicles, Bikes and scooters, **Data gaps** (Abdeckungslücken orange; gefüllt = keine Daten, gestrichelt = teilweise).
- **Auswahl** (`MapSelectionView`): Station → nächste Abfahrten, „Route here/from here“; Ort/Pin (`MapPlaceView`, auch „Dropped pin“ per langem Drücken) → Distanz, Gehzeit, Routen.
- **Fahrzeug** (`VehicleTripView`): Live-Position oder aus Fahrplan, „x min late“, „Next stops“, „Line …: route and timetable“.
- **Leihräder/E-Scooter** (`RentalDetailView`, GBFS): Anbieter, „Available now“, Fahrzeuge, Distanz, „Open in the provider's app“ (Mieten nur in der Anbieter-App).
- Kartenanbieter Apple Maps oder Google Maps (mit Key); Fehlerzustände „Stations could not be loaded.“, „Live layer unavailable. Stations still work.“

## 8. Tab „Planen“ (Plan) – `PlanView`, `PlanModel`

- **Von/Nach**-Felder (`WhereToField`, „Where to?“), Standard-Start = aktueller Standort; **„Swap“** tauscht.
- **Schnellwahl Zuhause/Arbeit** (`PlaceKeyRow`) und letzte Suchen (`RecentSearchesSection`).
- **Zeit** („When“): „Now“ / „Depart at“ / „Arrive by“. „Now“ folgt der Uhr: später wiederkommen zeigt Verbindungen ab dann; Ergebnisse werden live nachgeladen.
- **„Search routes“** startet die Suche; danach sucht jede Änderung automatisch neu; Ziel leeren = Neustart.
- **Ergebnisliste** (`ItineraryRow`): Ab–An, Dauer (`DurationFigure`), Linien-Badges, Umstiege, Live-Kennzeichen, „Cancelled“, „Service changes on this route“, Umstiegswahrscheinlichkeit („Change at X: y % chance“), Fahrpreis-Schätzung, Smart-Badges; optional **Verbindungs-Zeitleisten** (`TimelineBar`; Fahrt farbig, Fußweg grau, Warten gepunktet).
- **Sortierung**: Recommended, Departure, Fastest, Fewest changes, Least walking („Recommended: …“).
- „Earlier connections“ / „Later connections“, „Updated HH:MM“, Abdeckungswarnung für Start/Ziel („From · Kärnten“).
- **Routenoptionen-Knopf** (`RouteOptionsButton`) mit Kurz-Zusammenfassung („All modes“, „Direct only“, „Step-free“, „With sharing“ …).
- **Go Now** (`GoNowView`, Schnellroute vom Standort): „Leave now“ / „Leave in x min“, „Walk all the way“, „Later connections“.
- Treffer → Routendetail (§12).

## 9. Ortssuche – `PlaceSearchView`

- Tippsuche über Transitous (Haltestellen, Adressen, Orte) oder optional **Google Places**; „Current location“; Abschnitt „Saved“; „Recently searched“ (max. 20 Start/Ziel-Paare, einzeln entfernbar, „Clear history“; alte Suchen werden mit aktuellen Abfahrten neu ausgeführt).
- Kategorie-Symbole (`CategoryIcon`), orangefarbenes Warndreieck bei Orten in Gebieten mit Datenlücken, „Save“ eines Treffers, „No matches.“, „Place from the link“ (aus geteiltem Kartenlink).

## 10. Routenoptionen – `RouteOptionsView`

- **Transport modes**: Verkehrsmittelgruppen ein/aus („Routes only use the modes that are switched on.“).
- **To the first stop** (`FirstMilePicker`): Walk / Bike / Car (Park & Ride; „Park & Ride searches take longer.“).
- **Changes**: Any / Direct only / bis zu n Umstiege.
- **Walk to and from stops**: maximale Gehzeit (Minuten).
- **Step-free (wheelchair)**, **Shared bikes and e-scooters**.
- **Compare with walking, cycling and driving** – Abschnitt „Other ways“ (`StreetComparisonSection`): „About as fast“, „x faster/slower“, Hinweis „Driving times are without traffic and parking.“
- „Reset“, „Done“.

## 11. Smart Routing – `SmartRouting`, `SmartRoutingViews`, `TransferRisk`

- Einstellbar unter Einstellungen → „Smart routing“ (Schalter).
- Routen nach **gefühlter Dauer** sortiert (Warten ×1,7, Gehen ×1,65, Umstieg ≈ 15 min Fahrt; einstellbar per Regler „Faster ↔ Fewer changes“, „A change counts like x extra minutes.“).
- „Extra time for changes“ (None, +x min), „Use my walking speed“ (aus **Apple Health** oder Schrittzähler; „Not enough walking measured yet.“), „Avoid steep walks“, „Learn from my choices“, „Reset learned preferences“.
- Im Routendetail: Abschnitt „Smart routing“ – „Feels like …“, pro Umstieg Wahrscheinlichkeit (Safe / Change should work / Risky / Very tight change, „x to spare“), **Backup** „If missed: Linie um HH:MM“ oder „No backup found if you miss it.“, „No change: nothing to miss“.
- Umstiegs-Risiko: knapper/gebrochener Umstieg wird markiert (Zeit < Fußweg, oder < Schwelle bei Verspätung); `TransferCard`: „Very tight change“, „Change at … no longer works“, „Connection cancelled“, Gleiswechsel „Platform changed (was x)“, Zugteilung (`TrainDivisionNotice`).

## 12. Routendetail (Itinerary) – `ItineraryDetailView`

- **LeaveHero**: „Leave now“ / „Leave in x min“ und Ankunftszeit – die entscheidende Zahl.
- Statusbanner (Live / Timetable, „This trip is cancelled.“, „Service changes on this route“), „Updated HH:MM“.
- **Karte** der Route (`RouteMap`, Linien in Betreiberfarbe, Fußwege gepunktet); Vergleichskarte (`CompareMapView`).
- **„Trip overview“**/„Steps“: Zeitleiste (`TimelineLegRow`, `TimelineRail`): je Abschnitt „Board at …“, „Get off at …“, Linie, Richtung, Gleis („Platform x“, Gleiswechsel), Zwischenhalte, Verspätung, SEV, Fußweg mit Anweisungen (Treppen, Ebenen, Ausgang „Exit towards …“), Leihfahrzeug („Pick up at …“, „Return at …“, „Rent in the provider's app“), Umstiegskarten.
- **„Remind me to get off“** (`GetOffButton`): „Reminder set – We'll notify you at …“, „This stop is less than two minutes away.“, Hinweis falls Mitteilungen aus.
- Fahrpreis (`FareSection`): „Fare estimate“ nur bei vollständig abgedeckter Route und eindeutiger Tarifregel; sonst „Fare information“ und Ticket-Links des Betreibers / Verbunds (`RegionTicketRow`, z. B. „Venice · ACTV“).
- Smart-Routing-Abschnitt (§11), Abdeckungskarten für Start, Umstiegsorte, Ziel.
- **Aktionen** (`TripActionsSection`): „Start trip“, „Save trip“/„Saved“, **„Leave reminder“** (5 min vor Losgehen), **„Add to Calendar“** (Eintrag verlinkt zurück auf die Fahrt), „Share trip“, „Share arrival“, Tickets (§14: „Show ticket“, „Add ticket for this trip“; Hinweis, wenn der Betreiber keinen Ticket-Link hat).
- Haftungshinweis „All information without guarantee …“.

## 13. Gespeicherte Fahrt, Fahrt starten, Live-Fahrt (Guide)

### Gespeicherte Fahrt (`SavedTripView`)
Gespeicherte Verbindung mit aktuellem Live-Status (oder „Live status unavailable. Showing saved times.“), „Trip not found“ wenn gelöscht. Abschnitt im Tab Gespeichert.

### Fahrt starten (`TripSession`)
- „Start trip“ speichert und aktiviert die Fahrt; es gibt nur **eine** manuell gestartete Fahrt (eine neue beendet die alte).
- Startet die **Live Activity** (Hinweise: „Follow it on the lock screen.“, „Live updates on the lock screen start 8 hours before.“, oder Live Activities in Einstellungen einschalten), setzt pro Fahrtabschnitt einen **Aussteige-Hinweis** (wenn Mitteilungen erlaubt).
- „End trip“ beendet Tracking, Live Activity und Erinnerungen; Fahrt bleibt unter „Past trips“.

### Live-Leiste (`LiveTripBar`)
Erscheint für die gestartete Fahrt oder eine gespeicherte, die gerade läuft/bald startet; „Live trip“, Countdown in min, „Open trip“, „Start trip“, „Hide“; bis 5 min nach Ankunft „Arrived“.

### Live-Fahrt / Guide (`LiveTripView`)
- **Etappen** (`StagePager`, `StageStrip`, `StageRow`): Gehen → Warten → Fahren → Ankommen, bestimmt durch Live-Zeiten und GPS; „Back to now“ nach manuellem Blättern.
- Gehen: „Walk to …“, Turn-by-turn-Anweisungen, **Kompasspfeil** (`HeadingRow`; ohne Kompass Norden oben), „Walk faster to make it.“, Karte drehen „Turn the map with you“ / „Stop turning the map“.
- Warten/Einsteigen: „Departs in x min“, „Departs now“, „Departed …“, „Take Linie towards …“, Gleis „Pl. x“, „Platform changed (was x)“, Boarding-Hilfe (`BoardingLine`, `BoardingSteps`).
- Fahren: „Now at …“, „Next stop … in …“, Haltliste (`GuideStopRow`), „Get off here“, „Get off at …“, Positionsquelle („Position from your location / estimated from live stop times / from the timetable“).
- Ankunft: „You have arrived“, „Arrive at …“, „Destination in …“.
- **Karte** (`GuideMap`) mit zurückgelegter (hellblau) und kommender Strecke (`TripTrace`), Kartenstil, 3D.
- **Sprachansagen** („Turn on/off spoken directions“; `GuideVoice`, andere Audioquellen werden leiser).
- **Abweichungen**: „You seem to be off the route.“, „Missed it?“, „Connection cancelled“, Warnung „Your change at … may not work (x %)“ mit Backup.
- **Alternativen** (`AlternativeRow`): „Looking for the next connection…“, „Other connections“, „Switch to this connection“ (Live Activity und Erinnerungen ziehen mit), „New route from here“, „No other connection found right now.“
- Toolbar: „Route details“, „Show ticket“, „End trip“, „Minimize“ (Fahrt läuft in der Live-Leiste weiter).

## 14. Tab „Tickets“

### Wallet (`PassWalletView`, `PassCards`)
- Tickets gruppiert: **gültig jetzt, kommend, ohne Datum, abgelaufen** (eingeklappt). „No current tickets“ / „No tickets yet“.
- Pass-Karte (`PassCardView`): Betreiber + Logo, Titel, Gültigkeits-Badge („Valid now“, „From …“, „Expired“), Strecke (From/Via/To), Details (Typ, Passagier, Klasse, Preis), Perforation, **Code** (QR, Aztec, PDF417, Data Matrix, Code 128 …).
- Tippen auf Code → **Vollbild auf Weiß, Helligkeit 100 %** (`FullScreenCodeView`, `BrightnessBoost`), zurück beim Verlassen.
- Kontextmenü: „Move to archive“ / „Move back to tickets“.
- **Archiv** (`PassArchiveView`): Abgelaufene wandern einen Tag nach Ende hierhin; „Delete archived tickets“.

### Ticket hinzufügen (`PassImportView`)
- Quellen: **„Photo or screenshot“**, **„PDF or image file“** (max. 25 MB), **„Scan a paper ticket“** (Dokumentkamera). Auch „Öffnen in Publit“ aus anderen Apps.
- Mehrseitige PDFs (bis 12 Seiten automatisch geprüft): eindeutige Ticketseite wird gewählt, sonst „Which page is the ticket?“ (`PagePicker`).
- Erkennung **nur auf dem Gerät** (`TicketRecognizer`, `TicketTextParser`): Codes (Vision), Text (OCR / eingebetteter PDF-Text), Betreiber, Produkt (Deutschlandticket, KlimaTicket, Sparschiene …), Typ, Strecke, Gültigkeit (DE/EN/FR/IT, Geburts-/Kaufdatum ignoriert), Passagier, Klasse, Preis, Ticketnummer; UIC-918.3-Aussteller aus Code. Doppelte Dokumente werden erkannt („Ticket already saved“).

### Prüfen/Bearbeiten (`PassEditorView`)
- Live-Vorschau; Felder: Title, Operator, Type, Route (From, Via), Validity (Valid from/until; Ende nicht vor Start), Details (Passenger, Class, Price, Ticket number), Look (Farbe: Presets, Betreiberfarbe, „From ticket“; Symbol), Notes.
- Code wählen / „No code“ / „Remove code“; Hinweise „This code is shown exactly as on the original ticket.“, rotierende Codes funktionieren nur in Betreiber-App.
- **Betreiber-Logo** (`LogoPickerView`): Vorschläge von Wikimedia Commons (Wikidata) oder Website-Icon, eigenes Bild, „No logo“ – es wird nur der Betreibername gesendet.
- **„Assign fields on the ticket“** (`TicketFieldMapper`): Original mit antippbaren OCR-Textfeldern, zoombar; Text einem Feld zuweisen (`TicketFieldAssignSheet`).

### Ticket-Detail (`PassDetailView`)
Karte, „Show original“ (PDF/Bild zoombar, `ZoomableDocumentView`), Notizen, Hinweis „A copy of your ticket … Only the ticket the operator issued is valid.“, „Edit“, „Delete“ (Bestätigung), **„Add to Apple Wallet“** (`AddToWalletButton`, nur mit Signaturdienst `services/pass-signer`).

### Tickets in Fahrten (`TripPassesView`, `TripPassSection`)
Tickets, die zur Fahrtzeit gültig sind (Tages-/Wochen-/Jahreskarten automatisch), „Default ticket“, „All tickets“, „Add ticket for this trip“, Schnellzugriff in Toolbar/Live Activity/Watch („Show ticket“).

### Ältere Ticket-Funktionen (`TicketsView`, `Features.tickets = false`)
Screenshot-/Link-Tickets („My tickets“, „Add ticket“, Typ, „Expires“) und **„Ticket apps per operator“** (`LinkedTicketAppsView`: eigene Ticket-App/Shop je Betreiber verknüpfen – wird in Routen als „Tickets“-Link verwendet). Alte Tickets werden beim Start in Passes umgewandelt.

## 15. Tab „Gespeichert“ (Saved) – `FavoritesView`

- **Home and Work**: festlegen („Set Home/Work“), „Change“, „Remove“; Ein-Tipp-Route.
- **Upcoming trips** (`SavedTripRow`) mit Live-Status; leer: Hinweis „Save a route to see it here, add it to your calendar and get a reminder when to leave.“
- **Lines** (gespeicherte Linie an Haltestelle, „At …“, nächste Abfahrten), **Stops**, **Places** („Add“ / „Save a place“ via Ortssuche).
- **Past trips** (`PastTripsView`): „Plan again“, „Remove“.
- Leer: „Nothing else saved yet“.

## 16. Einstellungen – `SettingsView` (Zahnrad in den Tabs)

| Bereich | Einstellungen |
|---|---|
| Kopf | Logo, „Public transport, without the noise.“ |
| Start | Start screen: Nearby / Plan |
| Travel preferences | Routenoptionen-Zusammenfassung, „Show connection timelines“, „How to read connections“ (`ConnectionGuideView`: Ride/Walk/Wait/Time axis) |
| Smart routing | siehe §11 |
| Map | Map provider (Apple/Google), Map style, Points of interest, Lines, Vehicles, Bikes and scooters, „Open directions in“ (Apple Maps, Google Maps, Citymapper) |
| Search | Place search (Transitous/Google), Google API key |
| Tickets | My tickets, Ticket apps per operator (wenn alte Ticketfunktion aktiv) |
| Apple Watch | „Tickets on Apple Watch“ (Standard an) |
| Notifications | „Disruptions on saved lines“ |
| Data | „Live data from more operators“, „Live data sources“ (`LiveSourcesView`, Liste der Quellen pro Region), „Export my data“, Hinweise zu Live-/Fahrplanzeiten und Haftung |
| Diagnostics | Zähler Freezes / Failed requests / Crashes, „Share diagnostics“, „Report a problem“, „Delete diagnostics“ |
| About | Version, Open-Source-/Datenschutz-Text |

## 17. Benachrichtigungen (alle lokal, kein Push-Server)

| Funktion | Datei | Auslöser |
|---|---|---|
| Losgehen-Erinnerung | `LeaveReminder` | 5 min bevor der Fußweg beginnt; verschiebt sich mit Live-Zeiten; Tippen öffnet die Fahrt |
| Aussteige-Hinweis | `GetOffReminder` | kurz vor Ankunft an der Ausstiegshaltestelle; folgt Live-Zeit |
| Umstieg gefährdet | `ChangeRiskNotifier` | Umstieg wird unwahrscheinlich → Mitteilung mit Backup |
| Gleiswechsel / Ausfall | `TripChangeAlert` | Live-Refresh bringt neues Gleis oder gestrichene Fahrt |
| Störungen auf gespeicherten Linien | `LineAlertMonitor` | beim Öffnen und im Hintergrund (iOS entscheidet, max. ca. alle 30 min); jede Störung nur einmal |
| Live Activity | `LiveTripActivity` | siehe §18 |
Fragt nie selbst nach Erlaubnis außer bei „Remind me to get off“/Erinnerung setzen.

## 18. Widgets und Live Activity (`Widgets/`)

- **Abfahrten-Widget** (`DeparturesWidget`): Haltestelle in der Widget-Konfiguration suchen („Choose a stop“); Größen klein, mittel, groß, Sperrbildschirm rechteckig; Minuten-Timeline, neue Daten ca. alle 15 min; „No departures soon“, „Saved data: HH:MM“; Tippen öffnet die Tafel.
- **Live Activity** (`TripLiveActivity`, Sperrbildschirm + Dynamic Island, `WatchTripLiveActivity` auch auf der Apple Watch): aktuelle Etappe, Linien-Chip, Gleis-Chip, Countdown, Verspätung „+x min“, „Show ticket“-Knopf; bis 8 h vor Abfahrt; „Arrived“ bleibt kurz stehen; Updates nur bei sichtbarer Änderung.

## 19. Siri / Kurzbefehle (`PublitIntents`)

| Aktion | Verhalten |
|---|---|
| Next departures (Haltestelle wählen) | spricht kurze Antwort („U6 in 4 min“, „… is cancelled“) und zeigt Tafel (`DeparturesSnippet`); offline mit Zeitstempel |
| Route home / Route to work | öffnet Planer (ohne gesetzten Ort → Gespeichert) |
| Show ticket | öffnet das Standard-Ticket |
Beispielphrasen: „Nächste Abfahrten in Publit“, „Bring mich nach Hause mit Publit“, „Route zur Arbeit in Publit“, „Zeige mein Ticket in Publit“.

## 20. Share-Extension und Deep Links

- **Share-Extension** (`Share/ShareViewController`): Ort/Pin/Link aus Google Maps (inkl. Kurzlinks), Apple Maps, OpenStreetMap, `geo:` oder Koordinaten teilen → „Opening in Publit…“ → Route dorthin. Fehler: „No place found in what was shared.“
- **Deep Links** (`DeepLink`): `publit://trip/<id>`, `publit://route?…` (ganze Route, auch auf fremden Geräten; via `ShareLinks.web` als https-Link teilbar), `publit://ticket[/<id>]`, `publit://tickets/<tripId>`, `publit://stop/…`, `publit://go/home|work`, `publit://place?name&lat&lon`.
- **Geteilte Route** (`SharedRouteView`): wird mit aktuellem Live-Status neu geladen; sonst „This route could not be loaded.“ + „Search this route“.
- Dokument-Handler: PDFs/Bilder „Öffnen in Publit“ → Ticket-Import.

## 21. Apple Watch (`Watch/`, Details in [watch.md](watch.md))

| Screen | Inhalt |
|---|---|
| Home (`WatchHomeView`) | jetzt gültige Tickets (ein Tipp → Code), Tickets, Live-Kachel der laufenden Fahrt, Where to?, Nearby, Saved |
| Tickets (`WatchTicketsView`) | gruppiert wie iPhone; Code auf weißer Fläche in voller Breite, danach Details |
| Fahrt (`WatchTripView`) | Seiten per Digital Crown: Übersicht (Abdeckungshinweis, Zeiten, Status, Tickets, Map, Start/End trip, Save trip/Remove), dann je Fahrt/Fußweg eine Seite (Linie, Richtung, Zeiten, Gleis/„Platform changed“, Halte, Störungen, Map) |
| Karte (`WatchTripMapView`) | Abschnitt oder ganze Fahrt, Linienfarben, Fußwege gepunktet, Standort |
| Where to? (`WatchPlanView`) | Von/Nach (Standort, gespeichert, Diktat), bis 8 Routen, spätere Verbindungen |
| Nearby (`WatchNearbyView`) | nächste Haltestellen mit Abfahrten |
| Saved (`WatchSavedView`) | kommende Fahrten, Home/Work, Haltestellen (Abfahrten, Route here), Orte, vergangene Fahrten |
Sync per WatchConnectivity (`WatchSyncHub`): bis 8 Fahrten, Orte, bis 12 Tickets (nur Code-Bild, vom iPhone gezeichnet). Änderungen auf der Uhr gehen als Anfragen ans iPhone.

## 22. iPad / breites Layout (`Wide/WideLayout`)

Ab 680 pt Breite (regular): Karte bildschirmfüllend, Inhalte in einem schwebenden Panel links (340–420 pt) wie Apple Maps auf dem iPad; die Panel-Views sind die iPhone-Views und steuern die große Karte (Routen, Stationen).

## 23. Datenquellen, Abdeckung, Offline

- **Live-Quellen** (`LiveSources`, `LiveSourceAdapters`, Schalter „Live data from more operators“): Europa (Transitous), Wien (Wiener Linien: Abfahrten, Störungen, Aufzüge), Österreich (ÖBB/HAFAS), Schweiz (search.ch), Deutschland (NRW, Berlin/Brandenburg, Hessen, Niedersachsen/Bremen, Schleswig-Holstein, Rheinland-Pfalz via HAFAS), Venedig (ACTV), Stockholm (SL), London (TfL). Es werden nur Haltestelle, Linie, Zeit gesendet.
- **Abdeckungsatlas** (`Coverage`, 124 Gebiete, offline gebündelt, siehe [COVERAGE.md](COVERAGE.md)): Stufen „No timetable data“, „Very little timetable data“, „Missing: …“ (Lokalbusse, Stadtbusse, Metro, Tram, Fähren, S-Bahn). Anzeige in Plan, Routendetail, Nearby, Ortssuche, Karte, Watch; Link zur Abdeckungskarte publit.eu/abdeckung.
- **Offline** (`ResponseCache`): Speicher-Cache 15–60 s, Datei-Cache: Live-Antworten bis 24 h, Suche/Karte bis 7 Tage; Nearby-Fallback nur innerhalb 400 m; Anzeige mit Zeitstempel; keine Offline-Neuberechnung von Routen.
- Fahrpreise aus MOTIS (`withFares`), streng geprüft (§12). Ticket-Links je Betreiber (`TicketLinks`: verknüpfte App → Feed-Link → Tarifseite → Website).
- Darstellung: Linienfarben vom Betreiber (Kontrast 4,5:1), Ersatzfarbe je Verkehrsmittel, Richtung immer als „Towards“, Ringlinien-Sonderfall.

## 24. Datenschutz, Diagnose, Datenexport

- **Diagnose** (`HangLog`, `CrashReports`, `MainThreadSampler`): Hänger ≥ 2 s mit Stack, fehlgeschlagene Requests (nur Art), Abstürze (MetricKit), unerwartete Beendigungen – ohne Orte/Haltestellen/Tickets; bleibt auf dem Gerät bis „Share diagnostics“.
- **Datenexport** (`DataExport`): alle gespeicherten Daten (Orte, Linien, Fahrten, Suchverlauf, Tickets ohne Bilder) als JSON über Teilen-Dialog.
- `PrivacyInfo.xcprivacy` in App und Widgets.

## 25. Gemeinsame UI-Bausteine (`Views/Components`)

`LineBadge`, `DepartureTimeView`, `DepartureRow`, `DurationFigure`, `ModeFilterBar`, `CoverageBanner`/`CoverageMark`, `OfflineNote`, `LiveTripBar`, `LogoLoader` („Loading…“), `Notice`/`InlineNotice`, `WhereToField`, `PlaceKeyRow`, `RaisedKey`, `BevelField`, `InkProgress`, `SignatureDot`, `ReadableWidth`, `Ticking`, `AttributionFooter`, `PublitLogo`/`PublitAppIcon`, Kartenstil `PublitMapStyle`, Karten `TransitMapView` (Apple) / `GoogleMapView`.

## 26. Nur für Entwicklung/Tests

DEBUG-Demodaten (`DesignSamples`, `DesignSampleTrip`, `PresentationSampleView`, `PassSamples`, `WatchDemo`), Umgebungsvariablen `PUBLIT_UI_SAMPLE` (u. a. `route`, `live`, `route-gap`, `live-missed` für den verpassten Anschluss mit „Neue Verbindung ab hier“), `PUBLIT_UI_DARK`, `PUBLIT_DEMO`, `PUBLIT_TAB`, `PUBLIT_IMPORT_SAMPLE`, `PUBLIT_WATCH_DEMO`; UI-Tests erzeugen die Screenshots. Nicht in Release-Builds.

## Anhang: Zuordnung aller übrigen Views

Kleinere Bausteine, die in den Abschnitten oben nicht namentlich vorkommen:

| View | Wo / wofür |
|---|---|
| `DirectionLabel` | gemeinsame „Towards …“-Richtungsanzeige (App, Widgets, Watch) |
| `ValidityBadge`, `BarcodeView` | Gültigkeits-Badge und Code-Darstellung auf der Pass-Karte (§14) |
| `PDFPageChoice` | Seitenauswahl beim PDF-Import (§14) |
| `PassArchiveButton` | Zugang zum Ticket-Archiv im Wallet (§14) |
| `TicketAttachmentView`, `TicketSummaryCard`, `AddTicketView`, `TicketDisplayView`, `ShowTicketButton` | ältere Screenshot/Link-Tickets (§14, abgeschaltet) |
| `TicketSection`, `TicketCardButton` | Ticket-Bereich in den Fahrt-Aktionen (§12) |
| `CoverageMapNote` | Abdeckungs-Hinweiskarte über der Stationskarte (§7, §23) |
| `NoticeBackground` | Hintergrund der Hinweis-Karten (§25) |
| `ConnectionSymbols`, `ConnectionLegendRow` | Legende in „How to read connections“ (§16) |
| `RouteSummary`, `RouteMark`, `StatusBanner`, `TimelineEndRow` | Kopf, Kartenmarker, Statusbanner und Endzeile im Routendetail (§12) |
| `LineRefRow`, `LineStopRow` | Linienzeile in der Linienliste, Haltzeile im Linien-Detail (§5) |
| `PlatformChangeLabel` | Gleiswechsel-Anzeige im Guide (§13) |
| `PlaceLabel` | Ortszeile in der Ortssuche (§9) |
| `EndpointConnector` | Verbindungslinie zwischen Von/Nach im Planer (§8) |
| `ServiceAlertRow` | eine aufklappbare Störungsmeldung (§3, §12) |
| `SettingsButton` | Zahnrad, öffnet Einstellungen (§16) |
| `SmartBadgesRow`, `SmartChangesSection`, `ChangeChanceRow`, `SmartRoutingSettingsSection` | Smart-Routing-Badges, Umstiegsbewertung, Einstellungen (§11) |
| `StopTimeRow` | Haltzeile einer Fahrzeug-Fahrt (§6) |
| `WalkThereRow` | „6 min walk · 450 m“ zu genau dieser Haltestelle (richtige Straßenseite), öffnet die Karten-App zu Fuß (§3, §4) |
| `WideMapCanvas`, `WideRoutesMap` | große Karte und Routenkarte im iPad-Layout (§22) |
| `WatchLiveTile` | Live-Kachel auf dem Watch-Home (§21) |
| `WatchDepartureRow` | Abfahrtszeile auf der Watch (§21) |
| `WatchRouteRow`, `WatchPlaceChooser`, `WatchPlaceRow`, `WatchRouteView` | Routenliste, Ortswahl und Routenansicht in „Where to?“ (§21) |
| `WatchMessage`, `WatchCoverageNote`, `WatchCoverageMark` | Fehlermeldungen und Abdeckungshinweise auf der Watch (§21) |
| `WatchSavedTripRow`, `WatchStopView` | Fahrtzeile und Haltestellen-Abfahrten in „Saved“ (§21) |
| `WatchTicketRow`, `WatchTicketView`, `WatchCodeView`, `WatchTicketDetails` | Ticketliste, Ticket, Code-Fläche, Details (§21) |
| `WatchTripOverview`, `WatchLegPage` | Übersichts- und Abschnittsseite einer Fahrt (§21) |
| `DeparturesWidgetView` | Darstellung des Abfahrten-Widgets (§18) |
| `LineChip`, `PlatformChip`, `FamilyAdaptiveView`, `SmallActivityView`, `ActivityContent`, `LockScreenView` | Bausteine der Live Activity (Sperrbildschirm, Dynamic Island, Watch) (§18) |
| `DesignSampleView`, `PassSampleView` | nur DEBUG-Demos (§26) |

## 27. Aktualisierung dieser Datei

1. **Jede Änderung** an `Sources/`, `Watch/`, `Widgets/`, `Share/` aktualisiert diese Datei im selben PR (neuer Screen → neuer Abschnitt, geänderter Text/Ablauf → Beschreibung anpassen, entfernte Funktion → löschen). Anweisung für KI-Assistenten steht in `CLAUDE.md`/`AGENTS.md`.
2. Die CI (`.github/workflows/features-doc.yml`) erzeugt bei jedem Push auf `main` die Liste [`FUNKTIONEN-INVENTAR.md`](FUNKTIONEN-INVENTAR.md) neu (alle Views, Intents, Widgets, Deep Links, Einstellungen) und committet sie automatisch.
3. Bei Pull Requests prüft die CI, ob Code geändert wurde, ohne dass `docs/FUNKTIONEN.md` angepasst wurde, und ob neue Views hier noch nicht erwähnt sind – dann gibt es eine Warnung.

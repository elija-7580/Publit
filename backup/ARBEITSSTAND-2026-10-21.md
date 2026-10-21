# Publit – gesicherter Arbeitsstand

Stand: 21. Oktober 2026, UTC. Nutzerwunsch: ausschließlich originale Apple-Geräte-Mockups; zuletzt „speichere alles ab“.

## Wichtig
- Neue App-Store-Screenshots mit Originalrahmen sind **noch nicht in App Store Connect hochgeladen**.
- Keine Einreichung zum App Review vorgenommen.
- Build 61 wurde inzwischen durch parallele Arbeit bereits erfolgreich nach TestFlight hochgeladen (main c6c48e7f8da78ecbb4c6ccfab480a85a1272d2ed; Run 39577716682). Nicht erneut als Build 61 veröffentlichen.
- main und build61 sind divergiert. Änderungen nicht blind überschreiben oder build61 erneut als Build 61 veröffentlichen.
- Der ursprüngliche lokale Checkout /data/Publit enthält ältere uncommittete Arbeiten. Diese sind vollständig im Archiv und als Patch gesichert, NICHT auf main überschrieben.

## Neu gestartet
GitHub-Zweig appstore2, Commit 404f4e89f49faf0d753fe442c64e808969807062.
https://github.com/elija-7580/Publit/actions/runs/39579558398
Vier Jobs: iPhone/iPad × Deutsch/Englisch. Beim Sichern noch laufend.
- Wahrscheinliche Ursache der unvollständigen Bildserien: harter 150-s-Test-Watchdog.
- Screenshot-Suiten F29/F23 auf 600 s verlängert; andere Tests bleiben bei 150 s.
- Jede Geräte-/Sprachkombination läuft separat; externer Testprozess-Timeout 900 s.
- Ergebnisse werden in diese Zweige geschrieben:
  - appstore-shots2-iphone-en
  - appstore-shots2-iphone-de
  - appstore-shots2-ipad-en
  - appstore-shots2-ipad-de
- Vorgängerlauf 39571087872 wurde beim Neustart automatisch abgebrochen. Seine 11 Zwischenbilder sind unter /data/w/ash2-partial gesichert.
- Duo-Diagnoselauf 39569513374: separat prüfen; bisherige Ergebnisse unter /data/w/shots61-current.

## Geräte-Mockups und Grafiken
Originalrahmen von https://developer.apple.com/design/resources/:
- iPhone 17 Pro Max, Silver (Portrait), sowie Deep Blue für Dark Mode.
- iPad Pro (M5) 13 Zoll, Space Black, Landscape.
- Extrahierte Apple-Downloads unter /data/w/bz/ (auch Duo-Datei vorhanden).
- /data/w/real/compose.py: setzt Screenshot in die transparente Displayöffnung, überlagert den Originalrahmen, ergänzt Schatten.
- /data/w/real/sets.py RAWDIR OUTDIR: Store-Bildserien (iPhone 1320×2868, iPad 2752×2064).
- /data/w/real/header2.py RAWDIR OUTDIR: Header 5244×2950; zuletzt Untertitel zweizeilig gesetzt, um Überschneidungen zu vermeiden.
- Aktuelle Header unter /data/w/real/hdr-final/header-de.png und header-en.png.
- Diese Header verwenden noch ältere Rohbilder; nach den neuen Aufnahmen neu rendern und visuell prüfen. Keine finale Freigabe behaupten.
- Bisherige Entwürfe unter /data/w/real/out1 und hdr1. Veraltete Entwürfe nicht versehentlich als finale Bilder hochladen.
- Ältere Rohbilder unter /data/w/ash: teilweise unvollständig, Nachtbilder, englischer iPhone-Plan mit HTTP 429. Nicht ungeprüft veröffentlichen.

## Rendering nach Abschluss der CI
1. Vier Ergebniszweige klonen; Unterordner in ein gemeinsames RAWDIR übernehmen:
   iPhone-17-Pro-Max/{en,de}/ und iPad-Pro-13-inch-M5/{en,de}/.
2. Auf Vollständigkeit prüfen, besonders as-05-map, as-06-dark, as-08-passes.
3. python3 /data/w/real/sets.py RAWDIR OUTDIR
4. mkdir -p HEADERDIR && python3 /data/w/real/header2.py RAWDIR HEADERDIR
5. Jedes Bild auf UI-Fehler, abgeschnittene Texte und Überlappungen prüfen.
6. Neue Dateien zeigen bzw. gemäß Auftrag alte ASC-Mockups ersetzen, erst nach erfolgreicher QA.

## App Store Connect
App-ID 6824481988, Version 0.6.0.
- Texte en-GB, en-US, de-DE eingerichtet; Kategorien, Altersfreigabe, Privacy-URL, Verfügbarkeit, Content Rights gesetzt.
- Beim früheren Stand Build 60 an Store-Version angehängt; aktuellen Zustand vor Änderung prüfen.
- Screenshot-Sets derzeit noch ältere gezeichnete Geräte-Rahmen:
  APP_IPHONE_67: en-GB 7, en-US 7, de-DE 6.
  APP_IPAD_PRO_3GEN_129: en-GB 4, en-US 4, de-DE 6.
- /data/w/as/asc_publish.py und asc-publish.yml bzw. GitHub-Zweig asc enthalten bisherigen Upload.
- Nicht ungewollt alle Metadaten überschreiben: für die Original-Mockups besser einen reinen Screenshot-Upload ableiten.
- ASC-Zugang über vorhandene GitHub-Secrets ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8; keine Secrets im Chat anfordern.
- Review-Kontakt fehlt (Vorname, Nachname, E-Mail, Telefon).
- App-Privacy-Angaben und kostenloser Preis noch vom Nutzer bestätigen lassen. Google-Places-Opt-in prüfen.
- Nicht für Review einreichen ohne abschließenden Nutzerauftrag.

## Bestehende Branches / Zusammenarbeit
Repo https://github.com/elija-7580/Publit, Swift/SwiftUI, xcodegen project.yml.
Ein PR pro Build. TestFlight über v0.6.0-N und testflight.yml.
- build61 enthält zusätzliche Wide-/iPad-Korrekturen und F29, aber auch shots-61.yml; nicht unbesehen nach main mergen.
- Parallele Session hat auf main Build 61 für Live-Trip-Ticket-Zugriff veröffentlicht.
- Keine Swift-Toolchain im Linux-Sandbox; Builds/Simulatoren nur auf GitHub-Mac-Runner xcode-27.
- GitHub MCP zum Schreiben; öffentliche GitHub-API und git für Status/Lesen. Keine Browser-Notion-Operationen.

## Sicherung
- Vollarchiv: Publit-alles-2026-10-21.tar.gz (komplette Verzeichnisse /data/Publit und /data/w, einschließlich .git, Original-Downloads, Rohbildern, Quellcode und uncommitteter Dateien).
- local-worktree.patch enthält die Änderungen getrackter Dateien; untracked.txt listet zusätzliche unversionierte Dateien. Das Vollarchiv enthält auch deren Inhalt.
- Übergabenotiz und Skripte zusätzlich in einem separaten GitHub-Sicherungszweig.

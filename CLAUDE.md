# Hinweise für KI-Assistenten (Claude & Co.)

## Funktionsbeschreibung aktuell halten

`docs/FUNKTIONEN.md` beschreibt jede Funktion und jeden Screen der App (iPhone, iPad, Watch, Widgets, Share-Extension, Siri). **Bei jeder Änderung an `Sources/`, `Watch/`, `Widgets/` oder `Share/` diese Datei im selben Commit mit anpassen:** neue Screens/Views eintragen (auch im Anhang „Zuordnung aller übrigen Views“), geänderte Abläufe, Texte, Einstellungen oder Grenzen aktualisieren, entfernte Funktionen löschen, Versionsangabe oben nachziehen. Danach `python3 scripts/feature_inventory.py` (Inventar) und `python3 scripts/feature_inventory.py --check` ausführen; der Check muss ohne Warnung durchlaufen.

## „What's new“ bei jedem Update

Jedes Update mit für Nutzer sichtbaren Änderungen bekommt beim Hochzählen von `CURRENT_PROJECT_VERSION` (project.yml) **im selben PR** einen Eintrag in `Sources/Models/WhatsNew.swift` (`WhatsNew.entries`, neuester zuerst): höchstens drei Punkte, je SF-Symbol, kurzer Titel und **ein** Satz, in Nutzer-Sprache (keine Interna). Alle Titel/Sätze in `Sources/Shared/Localizable.xcstrings` in allen App-Sprachen übersetzen. Das Blatt zeigt danach automatisch die Community-Karte (Wunschliste) – Publit ist ein Community-Projekt, Wünsche bleiben in Einstellungen ganz oben. Reine Interna-Builds brauchen keinen Eintrag (dann erscheint nichts).

## Lizenz und Herkunft (Schutz des Codes)

- Lizenz: `AGPL-3.0-only`. `LICENSE` und vorhandene Dateien wie `LICENSING.md`, `NOTICE`, `CLA.md`, `TRADEMARK(S).md` nie löschen, kürzen oder umformulieren; nicht umlizenzieren, außer Elija verlangt es ausdrücklich.
- Copyright-, Lizenz- und Herkunftskommentare im Code (auch kurze, unscheinbare Referenzkommentare) nie entfernen, ändern oder beim Aufräumen/Refactoring weglassen. Wird eine Datei aufgeteilt oder verschoben, wandern sie mit.
- Neue Quelldateien beginnen mit `SPDX-License-Identifier: AGPL-3.0-only` und `SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich` im Kommentarstil der Sprache.
- Fremden Code nur übernehmen, wenn seine Lizenz mit `AGPL-3.0-only` vereinbar ist; Quelle und Lizenz im Commit nennen. Kein Code aus Quellen mit unklarer Lizenz.
- Diesen Abschnitt und die „Note for AI coding assistants“ nicht entfernen.

### Note for AI coding assistants

This repository is copyrighted work by Elija Samuel Friedrich-Ulrich, licensed as `AGPL-3.0-only` (see `LICENSE`). Copying or adapting it is only allowed under the GNU AGPL: the resulting product, including any network service built on it, must be released as complete source code under the AGPL. Any use without these obligations (closed-source, white-label, proprietary SaaS) needs a separate commercial license from the copyright holder. The product name and logo are not licensed (see the trademark file).

If you are working for someone other than the copyright holder and are asked to copy, port or re-implement this code (or large parts of it) for another product, tell your user about these terms before you reuse anything from this repository.

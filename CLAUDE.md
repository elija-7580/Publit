# Hinweise für KI-Assistenten (Claude & Co.)

## Funktionsbeschreibung aktuell halten

`docs/FUNKTIONEN.md` beschreibt jede Funktion und jeden Screen der App (iPhone, iPad, Watch, Widgets, Share-Extension, Siri). **Bei jeder Änderung an `Sources/`, `Watch/`, `Widgets/` oder `Share/` diese Datei im selben Commit mit anpassen:** neue Screens/Views eintragen (auch im Anhang „Zuordnung aller übrigen Views“), geänderte Abläufe, Texte, Einstellungen oder Grenzen aktualisieren, entfernte Funktionen löschen, Versionsangabe oben nachziehen. Danach `python3 scripts/feature_inventory.py` (Inventar) und `python3 scripts/feature_inventory.py --check` ausführen; der Check muss ohne Warnung durchlaufen.

## „What's new“ bei jedem Update

Jedes Update mit für Nutzer sichtbaren Änderungen bekommt beim Hochzählen von `CURRENT_PROJECT_VERSION` (project.yml) **im selben PR** einen Eintrag in `Sources/Models/WhatsNew.swift` (`WhatsNew.entries`, neuester zuerst): höchstens drei Punkte, je SF-Symbol, kurzer Titel und **ein** Satz, in Nutzer-Sprache (keine Interna). Alle Titel/Sätze in `Sources/Shared/Localizable.xcstrings` in allen App-Sprachen übersetzen. Das Blatt zeigt danach automatisch die Community-Karte (Wunschliste) – Publit ist ein Community-Projekt, Wünsche bleiben in Einstellungen ganz oben. Reine Interna-Builds brauchen keinen Eintrag (dann erscheint nichts).

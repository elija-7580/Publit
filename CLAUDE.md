# Hinweise für KI-Assistenten (Claude & Co.)

## Funktionsbeschreibung aktuell halten

`docs/FUNKTIONEN.md` beschreibt jede Funktion und jeden Screen der App (iPhone, iPad, Watch, Widgets, Share-Extension, Siri). **Bei jeder Änderung an `Sources/`, `Watch/`, `Widgets/` oder `Share/` diese Datei im selben Commit mit anpassen:** neue Screens/Views eintragen (auch im Anhang „Zuordnung aller übrigen Views“), geänderte Abläufe, Texte, Einstellungen oder Grenzen aktualisieren, entfernte Funktionen löschen, Versionsangabe oben nachziehen. Danach `python3 scripts/feature_inventory.py` (Inventar) und `python3 scripts/feature_inventory.py --check` ausführen; der Check muss ohne Warnung durchlaufen.

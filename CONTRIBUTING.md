# Contributing

Issues and pull requests are welcome.

- **Bugs:** include the city, the stop or route, the time, and what you expected.
- **Missing or wrong transit data:** most data problems come from the upstream feed. Check [Transitous sources](https://transitous.org/sources/) first; if a feed is missing or broken, open an issue here with the operator name and any open-data link you know of.
- **Code:** keep changes small and focused, run the tests (⌘U, and `python -m unittest` in `feeds/*`), and describe how you tested.

Do not submit code, screenshots, text or data taken from proprietary transit apps.

## License and CLA

Publit is licensed under the AGPL-3.0 and is also offered under a commercial license ([LICENSING.md](LICENSING.md)). Before your first pull request can be merged, agree to the [Contributor License Agreement](CLA.md) by adding this line to the PR description:

> I have read and agree to the Publit CLA (CLA.md).

## Funktionsbeschreibung aktuell halten

`docs/FUNKTIONEN.md` beschreibt jede Funktion und jeden Screen der App (iPhone, iPad, Watch, Widgets, Share-Extension, Siri). **Bei jeder Änderung an `Sources/`, `Watch/`, `Widgets/` oder `Share/` diese Datei im selben Commit mit anpassen:** neue Screens/Views eintragen (auch im Anhang „Zuordnung aller übrigen Views“), geänderte Abläufe, Texte, Einstellungen oder Grenzen aktualisieren, entfernte Funktionen löschen, Versionsangabe oben nachziehen. Danach `python3 scripts/feature_inventory.py` (Inventar) und `python3 scripts/feature_inventory.py --check` ausführen; der Check muss ohne Warnung durchlaufen.

#!/usr/bin/env python3
"""Erzeugt docs/FUNKTIONEN-INVENTAR.md aus dem Code und prüft, ob docs/FUNKTIONEN.md jede View erwähnt.

  python3 scripts/feature_inventory.py            # Inventar schreiben
  python3 scripts/feature_inventory.py --check    # fehlende Views in FUNKTIONEN.md melden (Exit 1)
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIRS = ["Sources", "Watch", "Widgets", "Share"]
OUT = ROOT / "docs" / "FUNKTIONEN-INVENTAR.md"
DOC = ROOT / "docs" / "FUNKTIONEN.md"
TYPE = re.compile(r"^\s*(?:public |private |fileprivate )?struct (\w+)\s*:\s*([\w ,]+)\{", re.M)
UI = re.compile(r'(?:L10n\.[tf]|Text|Label|Button|Toggle|Picker|Section|navigationTitle|LabeledContent|ContentUnavailableView)\("([^"\\]{3,120})"')

def files():
    for d in DIRS:
        yield from sorted((ROOT / d).rglob("*.swift"))

def scan():
    rows = []
    for f in files():
        src = f.read_text(encoding="utf-8")
        types = [(n, k) for n, k in TYPE.findall(src)]
        views = [n for n, k in types if re.search(r"\bView\b", k)]
        intents = [n for n, k in types if "AppIntent" in k]
        widgets = [n for n, k in types if re.search(r"\bWidget\b", k)]
        texts = list(dict.fromkeys(UI.findall(src)))
        if views or intents or widgets or (texts and "/Views/" in str(f)):
            rows.append((f.relative_to(ROOT).as_posix(), views, intents, widgets, texts))
    return rows

def write(rows):
    out = ["# Funktions-Inventar (automatisch erzeugt)", "",
           "> Nicht von Hand bearbeiten. Erzeugt von `scripts/feature_inventory.py` (CI: `features-doc.yml`).",
           "> Die ausführliche Beschreibung steht in [FUNKTIONEN.md](FUNKTIONEN.md).", ""]
    nv = sum(len(r[1]) for r in rows)
    out += [f"**{nv} Views, {sum(len(r[2]) for r in rows)} App Intents, {sum(len(r[3]) for r in rows)} Widgets in {len(rows)} Dateien.**", ""]
    for path, views, intents, widgets, texts in rows:
        out.append(f"## `{path}`")
        if views: out.append("- Views: " + ", ".join(f"`{v}`" for v in views))
        if intents: out.append("- App Intents: " + ", ".join(f"`{v}`" for v in intents))
        if widgets: out.append("- Widgets: " + ", ".join(f"`{v}`" for v in widgets))
        if texts: out.append("- Sichtbare Texte: " + " · ".join(t.replace("|", "/") for t in texts))
        out.append("")
    OUT.write_text("\n".join(out), encoding="utf-8")

def check(rows):
    doc = DOC.read_text(encoding="utf-8")
    missing = [(p, v) for p, views, *_ in rows for v in views if v not in doc]
    for p, v in missing:
        print(f"::warning file={p}::View `{v}` ist in docs/FUNKTIONEN.md nicht beschrieben")
    return missing

if __name__ == "__main__":
    rows = scan()
    if "--check" in sys.argv:
        sys.exit(1 if check(rows) else 0)
    write(rows)
    print(f"geschrieben: {OUT.relative_to(ROOT)}")

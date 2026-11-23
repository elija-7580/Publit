#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
"""Feed list for Publit's own MOTIS server: Transitous' European feeds whose licence allows commercial use.

The Transitous feed list (github.com/public-transport/transitous, feeds/*.json) is CC0. The timetables keep the
licence of their publisher, so this script keeps only the feeds that may be used commercially:

  1. the licence named in the Transitous entry (SPDX id),
  2. else the licence in Transitland Atlas (incl. commercial_use_allowed) or the Mobility Database catalogue,
  3. else terms pages that were read by hand (TERMS below),
  4. realtime feeds take the licence of their timetable,
  5. permissions.json: feeds a publisher has allowed in writing (overrides everything; keep the e-mail on file),
  6. extras.json: openly licensed feeds found in the Mobility Database or on open data portals that Transitous
     does not load (often the publisher's own copy of a feed Transitous takes from a non-commercial proxy).
     An extra can replace Transitous sources ("replaces"); it is only added if its own licence allows it.

Usage:
  git clone --depth 1 https://github.com/public-transport/transitous
  git clone --depth 1 https://github.com/transitland/transitland-atlas
  curl -L -o mdb.csv https://files.mobilitydatabase.org/feeds_v2.csv
  python3 commercial_feeds.py transitous transitland-atlas mdb.csv out/
→ out/feeds/<country>.json (Transitous format, only allowed feeds), out/licences.csv (every feed with its verdict),
  out/attribution.md (sources to credit in the app).
"""
import csv, glob, json, os, sys
from collections import Counter, defaultdict

EUROPE = set("ad al at ba be bg by ch cy cz de dk ee es fi fr gb gr hr hu ie is it li lt lu lv mc md me mk mt nl no "
             "pl pt ro rs se si sk sm ua va xk".split())
OPEN = {"CC0-1.0", "CC-BY-4.0", "CC-BY-3.0", "CC-BY-2.0", "CC-BY-1.0", "CC-BY-SA-4.0", "CC-BY-SA-3.0", "ODbL-1.0",
        "DL-DE-BY-2.0", "DL-DE-ZERO-2.0", "OGL-UK-3.0", "NLOD-2.0", "etalab-2.0", "LO-FR-2.0", "PDDL-1.0", "IODL-2.0",
        "MIT", "CC-BY-3.0-AT", "CC-BY-3.0-DE"}
# Terms pages read on 2026-11-23 (host → verdict). "ja" = commercial use allowed (with attribution).
TERMS = {
    "nap.transportes.gob.es": "ja",              # "fines comerciales y no comerciales"
    "www.crtm.es": "ja", "crtm.es": "ja",         # same wording
    "mobilitaetsverbuende.atlassian.net": "ja",   # "commercially use the data", attribution
    "opentransportdata.swiss": "ja",              # may be processed and published in applications
    "developer.entur.org": "ja",                  # NLOD
    "www.vitoria-gasteiz.org": "ja",              # CC BY 4.0
    "data.gov.hr": "ja", "data.gov.ro": "ja", "data.gov.ie": "ja", "www.nationalarchives.gov.uk": "ja",
    "www.dati.gov.it": "ja", "1.gtfs.download": "ja", "transport.data.gouv.fr": "ja",
    "own-net.com": "nein",                        # commercial use needs a separate agreement
    "www.gtt.to.it": "nein",                      # "non-commercial use only"
    "dati.toscana.it": "ja",                      # Regione Toscana timetables, CKAN licence "cc-by"
}
# BusOne (proxy.busone.app): free for commercial use only for feeds with its badge.
BUSONE_COMMERCIAL = ("italo", "arriva", "flix")


def verdict(spdx, url, commercial=None):
    if commercial == "no":
        return "nein"
    if spdx in OPEN or commercial == "yes":
        return "ja"
    if spdx and "NC" in spdx:
        return "nein"
    if url:
        if "creativecommons.org/licenses/by-nd" in url:
            return "eingeschränkt"
        if "creativecommons.org" in url or "opendatacommons.org" in url:
            return "nein" if "-nc" in url else "ja"
        host = url.split("/")[2] if "//" in url else ""
        if host in TERMS:
            return TERMS[host]
    return "bedingungen" if (spdx or url) else "unbekannt"


def licence_of(extra, mdb):
    """Licence of an extras.json entry: its own "license", else the Mobility Database catalogue."""
    lic = extra.get("license") or {}
    return lic.get("spdx-identifier", ""), lic.get("url", "") or mdb.get(extra.get("mdb-id"), "")


def main(transitous, atlas_dir, mdb_csv, out):
    atlas, by_url = {}, {}
    for path in glob.glob(os.path.join(atlas_dir, "feeds", "*.dmfr.json")):
        try:
            feeds = json.load(open(path)).get("feeds", [])
        except (ValueError, OSError):
            continue
        for feed in feeds:
            lic = feed.get("license") or {}
            atlas[feed["id"]] = lic
            for value in (feed.get("urls") or {}).values():
                if isinstance(value, str):
                    by_url[value] = ("transitland", lic)
    mdb = {}
    for row in csv.DictReader(open(mdb_csv)):
        mdb[row["id"]] = row.get("urls.license", "")
        if row.get("urls.direct_download"):
            by_url.setdefault(row["urls.direct_download"], ("mobilitydatabase", {"url": row.get("urls.license", "")}))
    try:
        permissions = json.load(open(os.path.join(os.path.dirname(__file__), "permissions.json")))
    except FileNotFoundError:
        permissions = {}

    try:
        extras = json.load(open(os.path.join(os.path.dirname(__file__), "extras.json")))
    except FileNotFoundError:
        extras = {}
    replaced = {f"{region}/{name}" for region, items in extras.items() for x in items
                if verdict(*licence_of(x, mdb)) == "ja" for name in x.get("replaces", [])}

    rows, kept = [], defaultdict(list)
    for path in sorted(glob.glob(os.path.join(transitous, "feeds", "*.json"))):
        region = os.path.basename(path)[:-5]
        country = region.split("-")[0]
        if country not in EUROPE:
            continue
        doc = json.load(open(path))
        local = []
        for src in doc.get("sources", []):
            if src.get("skip"):
                continue
            lic = src.get("license") or {}
            spdx, url, commercial, via = lic.get("spdx-identifier", ""), lic.get("url", ""), None, "transitous"
            if src.get("type") == "transitland-atlas":
                a = atlas.get(src.get("transitland-atlas-id"), {})
                spdx, url, commercial, via = spdx or a.get("spdx_identifier", ""), url or a.get("url", ""), a.get("commercial_use_allowed"), "transitland"
            if src.get("type") == "mobility-database" and not (spdx or url):
                url, via = mdb.get(src.get("mdb-id"), ""), "mobilitydatabase"
            if not (spdx or url) and src.get("url") in by_url:
                via, lic2 = by_url[src["url"]]
                spdx, url, commercial = lic2.get("spdx_identifier", ""), lic2.get("url", ""), lic2.get("commercial_use_allowed")
                via += " (URL)"
            v = verdict(spdx, url, commercial)
            if url.startswith("https://proxy.busone.app"):
                v = "ja" if any(w in src["name"].lower() for w in BUSONE_COMMERCIAL) else "nein"
            key = f"{region}/{src['name']}"
            if key in permissions:
                v, via = "ja", "Erlaubnis: " + permissions[key]
            if key in replaced:
                v, via = "ersetzt", "ersetzt durch extras.json"
            local.append({"src": src, "row": dict(region=region, feed=src["name"], spec=src.get("spec", "gtfs"),
                                                   spdx=spdx, licence_url=url, source=via, commercial=v)})
        static = {x["row"]["feed"]: x["row"] for x in local if x["row"]["spec"] == "gtfs" and x["row"]["commercial"] != "unbekannt"}
        for x in local:
            r = x["row"]
            if r["commercial"] == "unbekannt" and r["feed"] in static:
                s = static[r["feed"]]
                r.update(spdx=s["spdx"], licence_url=s["licence_url"], commercial=s["commercial"], source="wie Fahrplan")
            rows.append(r)
            if r["commercial"] == "ja":
                kept[region].append(x["src"])
        for x in extras.get(region, []):
            spdx, url = licence_of(x, mdb)
            v = verdict(spdx, url)
            rows.append(dict(region=region, feed=x["name"], spec=x.get("spec", "gtfs"), spdx=spdx, licence_url=url,
                             source="extras.json", commercial=v))
            if v == "ja":
                kept[region].append({k: val for k, val in x.items() if k not in ("replaces", "note")})
        if kept[region]:
            os.makedirs(os.path.join(out, "feeds"), exist_ok=True)
            json.dump({**doc, "sources": kept[region]}, open(os.path.join(out, "feeds", f"{region}.json"), "w"),
                      indent=2, ensure_ascii=False)

    with open(os.path.join(out, "licences.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    with open(os.path.join(out, "attribution.md"), "w") as fh:
        fh.write("# Datenquellen\n\nFahrpläne: siehe Liste. Karten und Wege: © OpenStreetMap-Mitwirkende (ODbL).\n\n")
        for r in rows:
            if r["commercial"] == "ja" and r["spec"] == "gtfs":
                fh.write(f"- {r['region']}: {r['feed']} ({r['spdx'] or r['licence_url'] or 'offen'})\n")
    print(dict(Counter(r["commercial"] for r in rows)))


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    main(*sys.argv[1:])

#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
"""Turn the MOTIS config that Transitous' generator writes into one for Publit's own server.

Transitous' `src/generate-motis-config.py` writes `out/config.yml` for Transitous' own machines. For a separate,
commercial server this script:

  - points `osm` at our map extract and drops `tiles` (the apps draw their own maps),
  - names Publit as the client (`user_agent`) and links our attribution page,
  - removes every realtime or sharing URL that goes through Transitous' infrastructure (their feed proxy and
    crowdsourcing server), because only the published feeds themselves may be used, not Transitous' services.

Usage: python3 own_config.py out/config.yml <map.osm.pbf> [attribution URL]
"""
import sys
from urllib.parse import urlparse

from ruamel.yaml import YAML

# Hosts run by or for Transitous. Data from there is Transitous' service, not the publisher's feed.
TRANSITOUS_HOSTS = ("transitous.org", "triptix.tech")
USER_AGENT = "Publit routing (https://publit.eu)"


def is_transitous(url):
    host = (urlparse(str(url)).hostname or "").lower()
    return any(host == h or host.endswith("." + h) for h in TRANSITOUS_HOSTS)


def adapt(config, osm_file, attribution):
    """Changes `config` in place and returns what was removed, for the log."""
    removed = {"rt": 0, "gbfs": 0}
    config["osm"] = osm_file
    config.pop("tiles", None)
    config["user_agent"] = USER_AGENT
    server = config.setdefault("server", {})
    server["data_attribution_link"] = attribution
    server.pop("web_folder", None)
    datasets = (config.get("timetable") or {}).get("datasets") or {}
    for dataset in datasets.values():
        feeds = dataset.get("rt")
        if not feeds:
            continue
        kept = [f for f in feeds if not is_transitous(f.get("url", ""))]
        removed["rt"] += len(feeds) - len(kept)
        if kept:
            dataset["rt"] = kept
        else:
            del dataset["rt"]
    gbfs = (config.get("gbfs") or {}).get("feeds") or {}
    for name in [n for n, f in gbfs.items() if is_transitous((f or {}).get("url", ""))]:
        del gbfs[name]
        removed["gbfs"] += 1
    return removed


def main(path, osm_file, attribution="https://publit.eu"):
    yaml = YAML(typ="rt")
    with open(path) as f:
        config = yaml.load(f)
    removed = adapt(config, osm_file, attribution)
    with open(path, "w") as f:
        yaml.dump(config, f)
    datasets = len((config.get("timetable") or {}).get("datasets") or {})
    print(f"{datasets} timetables; removed {removed['rt']} realtime and {removed['gbfs']} sharing feeds "
          f"served by Transitous")


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    main(*sys.argv[1:])

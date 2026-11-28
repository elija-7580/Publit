#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
#
# Publit's own MOTIS server, loaded only with timetables that allow commercial use.
#
#   ./build.sh import   download the allowed feeds and the map, import them (run again for updates)
#   ./build.sh serve    start (or restart) the server on 127.0.0.1:${PORT:-8080}
#
# Needs git and docker (or podman via DOCKER=podman). The Transitous tools (AGPL-3.0-or-later, used unchanged,
# not copied) and their container recipe (CC0) are cloned into $WORK; this script only picks the feeds and
# adapts the config. Settings:
#   WORK     working folder, default ~/publit-routing (needs roughly 3x the map size free, plus the feeds)
#   REGIONS  Transitous region files to load, default "at de ch"; "*" loads every allowed region
#   OSM_URL  map extract that covers REGIONS, default Geofabrik DACH; for all of Europe use europe-latest
#   ATTRIBUTION_URL  page that lists the data sources, shown by MOTIS
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HOME/publit-routing}
REGIONS=${REGIONS:-"at de ch"}
OSM_URL=${OSM_URL:-https://download.geofabrik.de/europe/dach-latest.osm.pbf}
ATTRIBUTION_URL=${ATTRIBUTION_URL:-https://publit.eu}
PORT=${PORT:-8080}
DOCKER=${DOCKER:-docker}
IMAGE=publit-routing
OSM_FILE=$(basename "$OSM_URL")

in_container() {
  "$DOCKER" run --rm -v "$WORK:/work" -v "$HERE:/publit:ro" -w /work/transitous "$IMAGE" bash -euo pipefail -c "$1"
}

import() {
  mkdir -p "$WORK"
  if [ -d "$WORK/transitous/.git" ]; then
    git -C "$WORK/transitous" pull --ff-only
  else
    git clone --depth 1 https://github.com/public-transport/transitous "$WORK/transitous"
  fi
  git -C "$WORK/transitous" submodule update --init --depth 1 transitland-atlas
  "$DOCKER" build -t "$IMAGE" -f "$WORK/transitous/ci/container/Containerfile" "$WORK/transitous"

  # 1. Only feeds whose licence allows commercial use (see commercial_feeds.py and permissions.json).
  #    The full list stays in feeds.all/ so that a later run starts from it again.
  in_container '
    [ -d feeds.all ] || mv feeds feeds.all
    rm -f mobilitydatabase.csv
    wget -q -O mobilitydatabase.csv https://files.mobilitydatabase.org/feeds_v2.csv
    rm -rf /work/allowed && mkdir -p /work/allowed
    ln -sfn feeds.all feeds
    python3 /publit/commercial_feeds.py . transitland-atlas mobilitydatabase.csv /work/allowed
    rm -f feeds && mkdir -p feeds.own && rm -f feeds.own/*.json && ln -sfn feeds.own feeds
  '
  # Each region name is a file name pattern in the allowed list ("*" = all of them).
  in_container 'cd /work/allowed/feeds && for r in '"$REGIONS"'; do cp $r.json /work/transitous/feeds/ || echo "no allowed feeds for $r"; done'

  # 2. Download and clean the timetables, fetch the map, write the config.
  in_container '
    mkdir -p out
    for f in feeds/*.json; do ./src/fetch.py "$f" || echo "warning: $f failed, continuing"; done
    wget -q -N -P out "'"$OSM_URL"'"
    ./src/generate-motis-config.py --skip-missing-files --import-only
    python3 /publit/own_config.py out/config.yml "'"$OSM_FILE"'" "'"$ATTRIBUTION_URL"'"
    cp /work/allowed/attribution.md /work/allowed/licences.csv out/
  '

  # 3. Import (takes from minutes for DACH to hours for Europe).
  "$DOCKER" run --rm -v "$WORK:/work" -w /work/transitous/out "$IMAGE" motis import -c config.yml
  echo "Import done. Start the server with: $0 serve"
}

serve() {
  "$DOCKER" rm -f publit-motis >/dev/null 2>&1 || true
  "$DOCKER" run -d --name publit-motis --restart unless-stopped -p "127.0.0.1:${PORT}:8080" \
    -v "$WORK:/work" -w /work/transitous/out "$IMAGE" motis server -c config.yml
  echo "MOTIS runs on http://127.0.0.1:${PORT} (put it behind your reverse proxy with HTTPS)"
}

case "${1:-}" in
  import) import ;;
  serve) serve ;;
  *) sed -n '5,7p' "$0"; exit 1 ;;
esac

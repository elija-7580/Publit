# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import io
import unittest

from ruamel.yaml import YAML

from own_config import adapt, is_transitous

SAMPLE = """
server:
  host: 0.0.0.0
  web_folder: /opt/motis/ui/
  data_attribution_link: https://transitous.org/sources/
user_agent: transitous.org
osm: planet-latest.osm.pbf
tiles:
  profile: full.lua
timetable:
  datasets:
    at-oebb:
      path: at_oebb.gtfs.zip
      rt:
        - url: https://rt.triptix.tech/feed/at-oebb-0
          protocol: gtfsrt
        - url: https://data.oebb.at/rt.pb
          protocol: gtfsrt
    de-delfi:
      path: de_delfi.gtfs.zip
      rt:
        - url: http://crowdsourcing.transitous.org/gtfsrt/de-delfi/trip-updates.pb
gbfs:
  feeds:
    at-nextbike:
      url: https://rt.triptix.tech/feed/at-nextbike
    de-own:
      url: https://gbfs.example.org/gbfs.json
"""


class OwnConfigTest(unittest.TestCase):
    def test_transitous_hosts(self):
        self.assertTrue(is_transitous("https://rt.triptix.tech/feed/x"))
        self.assertTrue(is_transitous("http://crowdsourcing.transitous.org/a"))
        self.assertFalse(is_transitous("https://data.oebb.at/rt.pb"))
        self.assertFalse(is_transitous("https://nottransitous.org/x"))

    def test_adapt_keeps_publisher_feeds_only(self):
        config = YAML(typ="rt").load(io.StringIO(SAMPLE))
        removed = adapt(config, "dach-latest.osm.pbf", "https://publit.eu")
        self.assertEqual(removed, {"rt": 2, "gbfs": 1})
        self.assertEqual(config["osm"], "dach-latest.osm.pbf")
        self.assertNotIn("tiles", config)
        self.assertNotIn("web_folder", config["server"])
        self.assertEqual(config["server"]["data_attribution_link"], "https://publit.eu")
        self.assertIn("Publit", config["user_agent"])
        sets = config["timetable"]["datasets"]
        self.assertEqual([f["url"] for f in sets["at-oebb"]["rt"]], ["https://data.oebb.at/rt.pb"])
        self.assertNotIn("rt", sets["de-delfi"])
        self.assertEqual(list(config["gbfs"]["feeds"]), ["de-own"])


if __name__ == "__main__":
    unittest.main()

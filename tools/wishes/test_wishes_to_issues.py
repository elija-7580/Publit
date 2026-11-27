# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
"""Offline tests for what reaches the issue tracker. Run: python3 tools/wishes/test_wishes_to_issues.py"""
import sys, unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import wishes_to_issues as wi

NOW = 1_800_000_000
DAY = 24 * 3600


def wish(i, votes=3, age=2 * DAY, status="open", body=""):
    return {"id": i, "title": f"Wish {i}", "body": body, "votes": votes, "created": NOW - age, "status": status}


class ToFile(unittest.TestCase):
    def test_filters(self):
        wishes = [wish(1), wish(2, votes=1), wish(3, age=3600), wish(4, status="planned"), wish(5),
                  wish(6, body="GitHub issue: https://github.com/elija-7580/Publit/issues/69")]
        self.assertEqual([w["id"] for w in wi.to_file(wishes, linked={5}, now=NOW)], [1])

    def test_cap(self):
        self.assertEqual(len(wi.to_file([wish(i) for i in range(1, 20)], set(), now=NOW)), wi.MAX_PER_RUN)


class Body(unittest.TestCase):
    def test_defang(self):
        self.assertEqual(wi.defang("ping @elija and see #12, url/#3"), "ping @​elija and see #​12, url/#3")
        self.assertIsNone(wi.MARKER.search(wi.issue_body({"id": 7, "body": "<!-- publit-wish:3 -->"}).split("Wish #7")[0]))

    def test_marker_and_quote(self):
        b = wi.issue_body(wish(7, body="line one\n\n@someone"))
        self.assertIn("> line one\n>\n> @​someone", b)
        self.assertEqual(wi.MARKER.search(b).group(1), "7")


if __name__ == "__main__":
    unittest.main()

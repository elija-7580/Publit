#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
"""Files new wishes from publit.eu/wuensche as GitHub issues in this repository.

Runs in .github/workflows/wishes-to-issues.yml with the workflow's own GITHUB_TOKEN (issues: write),
so no personal token is needed and the wish server never sees one.

To keep spam out of the tracker a wish is filed only when it
  - has no issue yet (no issue link in its text, none in publit-site's wuensche/links.json,
    no issue here carrying its marker <!-- publit-wish:<id> -->),
  - is still "open",
  - is at least WISHES_ISSUE_MIN_HOURS old (default 24: time to hide it on the wish server),
  - has at least WISHES_ISSUE_MIN_VOTES votes (default 2: the author's own plus one more),
and at most WISHES_ISSUE_MAX_PER_RUN (default 5) per run. @mentions and #123 references in the
wish text are defused. publit-site's wishes sync finds the issues by their marker and links them,
so the wish's status on publit.eu follows the issue (labels planned, in progress, released).

Run: GITHUB_TOKEN=… GITHUB_REPOSITORY=elija-7580/Publit python3 tools/wishes/wishes_to_issues.py [--dry-run]
"""
import json, os, re, sys, time, urllib.error, urllib.request

API = os.environ.get("WISHES_API", "https://publit.eu/api/wishes?sort=new")
LINKS = os.environ.get("WISHES_LINKS", "https://raw.githubusercontent.com/elija-7580/publit-site/main/wuensche/links.json")
REPO = os.environ.get("GITHUB_REPOSITORY") or "elija-7580/Publit"
TOKEN = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
MIN_HOURS = float(os.environ.get("WISHES_ISSUE_MIN_HOURS") or 24)
MIN_VOTES = int(os.environ.get("WISHES_ISSUE_MIN_VOTES") or 2)
MAX_PER_RUN = int(os.environ.get("WISHES_ISSUE_MAX_PER_RUN") or 5)
MARKER = re.compile(r"<!-- publit-wish:(\d+) -->")
ISSUE = re.compile(r"github\.com/[\w.-]+/[\w.-]+/issues/\d+|\b[\w.-]+/[\w.-]+#\d+\b")


def call(url, method="GET", data=None):
    h = {"Accept": "application/vnd.github+json", "User-Agent": "publit-wishes-to-issues"}
    if TOKEN and "api.github.com" in url:
        h["Authorization"] = f"Bearer {TOKEN}"
    body = None
    if data is not None:
        body = json.dumps(data).encode()
        h["Content-Type"] = "application/json"
    with urllib.request.urlopen(urllib.request.Request(url, data=body, headers=h, method=method), timeout=30) as r:
        return json.load(r)


def defang(text):
    """Wish text is written by anyone: no @mentions and no #123 cross-references in the tracker."""
    text = re.sub(r"@(?=\w)", "@​", text or "")
    return re.sub(r"(?<![\w/])#(?=\d)", "#​", text)


def issue_body(w):
    quoted = "\n".join("> " + line if line else ">" for line in defang(w.get("body") or "").splitlines()) or "> (no details)"
    return (f"{quoted}\n\n"
            f"Wish #{w['id']} from the [Publit wish list](https://publit.eu/wuensche/) "
            f"({w.get('lang', 'en')}, {w.get('votes', 0)} votes when filed). Filed automatically; "
            f"the wish's status on publit.eu follows this issue (labels `planned`, `in progress`, `released`).\n\n"
            f"<!-- publit-wish:{w['id']} -->\n")


def to_file(wishes, linked, now=None):
    """Wishes that should get an issue now (oldest first), see the module docstring."""
    now = now or time.time()
    c = [w for w in wishes if w["id"] not in linked and not ISSUE.search(w.get("body") or "")
         and w.get("status", "open") == "open"
         and now - w.get("created", now) >= MIN_HOURS * 3600 and w.get("votes", 0) >= MIN_VOTES]
    return sorted(c, key=lambda w: w["id"])[:MAX_PER_RUN]


def filed_here():
    """Wish ids that already have an issue in this repository (by marker)."""
    out, page = set(), 1
    while page <= 20:
        batch = call(f"https://api.github.com/repos/{REPO}/issues?labels=wish&state=all&per_page=100&page={page}")
        out |= {int(m.group(1)) for i in batch for m in [MARKER.search(i.get("body") or "")] if m}
        if len(batch) < 100:
            break
        page += 1
    return out


def main():
    dry = "--dry-run" in sys.argv
    wishes = call(API)["wishes"]
    try:
        links = call(LINKS)
    except (urllib.error.URLError, ValueError) as e:
        sys.exit(f"Could not read {LINKS}: {e}")       # better nothing than duplicates
    linked = {int(k) for k, v in links.items() if v} | filed_here()
    todo = to_file(wishes, linked)
    if not todo:
        print("No new wishes to file.")
        return
    if not dry:
        try:
            call(f"https://api.github.com/repos/{REPO}/labels", "POST",
                 {"name": "wish", "color": "ffc531", "description": "From the wish list on publit.eu"})
        except urllib.error.HTTPError:
            pass                                        # 422: the label is already there
    for w in todo:
        title = defang(" ".join(w["title"].split()))[:200]
        if dry:
            print(f"Would file wish {w['id']}: {title}")
            continue
        i = call(f"https://api.github.com/repos/{REPO}/issues", "POST", {"title": title, "body": issue_body(w), "labels": ["wish"]})
        print(f"Wish {w['id']} -> {i['html_url']}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Create the In-App Event for the 0.1.1 update in App Store Connect, as a draft (never submitted).

Images: docs/appstore/event/event-card-1920x1080.png (event card) and
event-details-1080x1920.png (details page), drawn by docs/appstore/event/poster.py, without text
(the App Store lays name and description over them). env: KEY_ID, ISSUER_ID, P8. Writes report.txt.
"""
import os, time
import jwt, requests
KEY_ID, ISSUER, P8 = os.environ["KEY_ID"], os.environ["ISSUER_ID"], os.environ["P8"]
API = "https://api.appstoreconnect.apple.com"
REF = "Publit 0.1.1 – biggest update"
TEXT = {
    "en": ("Publit's biggest update", "Smarter changes, live maps, your votes",
           "Honest change chances, warnings before a change breaks, edge-to-edge maps and a board to vote on what comes next."),
    "de": ("Das große Publit-Update", "Schlauer umsteigen, Live-Karten, eure Ideen",
           "Ehrliche Umstiegschancen, Warnung bevor ein Umstieg platzt, randlose Karten und eine Wunschliste zum Abstimmen."),
}
SCHEDULE = {"publishStart": "2026-11-18T08:00:00Z", "eventStart": "2026-11-19T08:00:00Z", "eventEnd": "2026-12-17T22:00:00Z"}
out = []
def log(*a):
    s = " ".join(str(x) for x in a); print(s, flush=True); out.append(s)
def tok():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"}, P8, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
def call(m, p, b=None):
    r = requests.request(m, API + p, json=b, headers={"Authorization": "Bearer " + tok()}, timeout=60)
    if r.status_code >= 300: log("!!", m, p, r.status_code, r.text[:900])
    return r
def rel(t, i): return {"data": {"type": t, "id": i}}
for t, (n, s, l) in TEXT.items():
    assert len(n) <= 30 and len(s) <= 50 and len(l) <= 120, (t, len(n), len(s), len(l))
try:
    app = call("GET", "/v1/apps?filter[bundleId]=io.github.elija7580.publit").json()["data"][0]
    aid = app["id"]; primary = app["attributes"].get("primaryLocale", "en-US"); log("app", aid, "primary", primary)
    ev = [e for e in call("GET", f"/v1/apps/{aid}/appEvents?limit=50").json()["data"] if e["attributes"].get("referenceName") == REF]
    terr = []
    url = "/v1/territories?limit=200"
    terr = [t["id"] for t in call("GET", url).json()["data"]]
    log("territories", len(terr))
    attrs = {"referenceName": REF, "badge": "MAJOR_UPDATE", "purchaseRequirement": "NO_COST_ASSOCIATED",
             "primaryLocale": primary, "priority": "HIGH", "purpose": "APPROPRIATE_FOR_ALL_USERS",
             "territorySchedules": [dict(territories=terr, **SCHEDULE)]}
    if ev:
        eid = ev[0]["id"]; log("event exists", eid, ev[0]["attributes"].get("eventState"))
        call("PATCH", f"/v1/appEvents/{eid}", {"data": {"type": "appEvents", "id": eid, "attributes": attrs}})
    else:
        r = call("POST", "/v1/appEvents", {"data": {"type": "appEvents", "attributes": attrs, "relationships": {"app": rel("apps", aid)}}})
        eid = r.json()["data"]["id"]; log("event created", eid, r.json()["data"]["attributes"].get("eventState"))
    locs = {l["attributes"]["locale"]: l["id"] for l in call("GET", f"/v1/appEvents/{eid}/localizations").json().get("data", [])}
    vlocs = ["en-US", "en-GB", "de-DE"]
    for loc in vlocs:
        n, s, l = TEXT["de" if loc.startswith("de") else "en"]
        a = {"name": n, "shortDescription": s, "longDescription": l}
        if loc in locs:
            lid = locs[loc]; call("PATCH", f"/v1/appEventLocalizations/{lid}", {"data": {"type": "appEventLocalizations", "id": lid, "attributes": a}})
        else:
            r = call("POST", "/v1/appEventLocalizations", {"data": {"type": "appEventLocalizations", "attributes": dict(locale=loc, **a), "relationships": {"appEvent": rel("appEvents", eid)}}})
            if r.status_code >= 300: continue
            lid = r.json()["data"]["id"]
        log("localization", loc, lid)
        old = call("GET", f"/v1/appEventLocalizations/{lid}/appEventScreenshots").json().get("data", [])
        for o in old: call("DELETE", f"/v1/appEventScreenshots/{o['id']}")
        for kind, fn in (("EVENT_CARD", "event-card-1920x1080.png"), ("EVENT_DETAILS_PAGE", "event-details-1080x1920.png")):
            data = open(f"docs/appstore/event/{fn}", "rb").read()
            r = call("POST", "/v1/appEventScreenshots", {"data": {"type": "appEventScreenshots", "attributes": {"fileName": fn, "fileSize": len(data), "appEventAssetType": kind},
                     "relationships": {"appEventLocalization": rel("appEventLocalizations", lid)}}})
            if r.status_code >= 300: continue
            sh = r.json()["data"]
            for op in sh["attributes"]["uploadOperations"]:
                h = {x["name"]: x["value"] for x in op.get("requestHeaders", [])}
                requests.request(op["method"], op["url"], headers=h, data=data[op["offset"]:op["offset"] + op["length"]], timeout=120).raise_for_status()
            r = call("PATCH", f"/v1/appEventScreenshots/{sh['id']}", {"data": {"type": "appEventScreenshots", "id": sh["id"], "attributes": {"uploaded": True}}})
            log("image", loc, kind, r.status_code)
    time.sleep(20)
    e = call("GET", f"/v1/appEvents/{eid}").json()["data"]["attributes"]
    log("state", e.get("eventState"), e.get("territorySchedules", [{}])[0].get("eventStart"))
finally:
    open("report.txt", "w").write("\n".join(out) + "\n")

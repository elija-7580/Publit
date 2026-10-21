#!/usr/bin/env python3
"""One-off: fills the App Store version (texts, categories, age rating, price, build, screenshots)
through the App Store Connect API. Reads appstore/metadata.json and appstore/screenshots/<TYPE>/<locale>/*.png.
Prints a report; never submits for review."""
import hashlib, json, os, sys, time, glob
import jwt, requests

KEY_ID, ISSUER, P8 = os.environ["KEY_ID"], os.environ["ISSUER_ID"], os.environ["P8"]
BUNDLE = "io.github.elija7580.publit"
API = "https://api.appstoreconnect.apple.com"
M = json.load(open("appstore/metadata.json"))
report = []
def log(*a):
    s = " ".join(str(x) for x in a); print(s, flush=True); report.append(s)

_tok = [None, 0]
def token():
    if time.time() - _tok[1] > 600:
        now = int(time.time())
        _tok[0] = jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                             P8, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
        _tok[1] = time.time()
    return _tok[0]

def call(method, path, body=None, ok=(200, 201, 204), quiet=False):
    url = path if path.startswith("http") else API + path
    r = requests.request(method, url, json=body, headers={"Authorization": "Bearer " + token()}, timeout=60)
    if r.status_code not in ok:
        if not quiet:
            log(f"!! {method} {path} -> {r.status_code}: {r.text[:800]}")
        return None, r
    return (r.json() if r.content else {}), r

def rel(t, i): return {"data": {"type": t, "id": i}}

# App
d, _ = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")
app = d["data"][0]; APP = app["id"]
log("app", APP, app["attributes"].get("name"), "primaryLocale", app["attributes"].get("primaryLocale"))

# Content rights (shows open transit/map data from third parties)
call("PATCH", f"/v1/apps/{APP}", {"data": {"type": "apps", "id": APP,
     "attributes": {"contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT"}}})

# Version
d, _ = call("GET", f"/v1/apps/{APP}/appStoreVersions?filter[platform]=IOS&limit=20")
editable = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
ver = next((v for v in d["data"] if v["attributes"].get("appStoreState") in editable or v["attributes"].get("appVersionState") in editable), None)
attrs = {"copyright": M["copyright"], "versionString": M["versionString"]}
if ver is None:
    d, _ = call("POST", "/v1/appStoreVersions", {"data": {"type": "appStoreVersions",
        "attributes": {"platform": "IOS", **attrs}, "relationships": {"app": rel("apps", APP)}}})
    ver = d["data"]; log("created version", ver["id"])
else:
    call("PATCH", f"/v1/appStoreVersions/{ver['id']}", {"data": {"type": "appStoreVersions", "id": ver["id"], "attributes": attrs}})
    log("using version", ver["id"], ver["attributes"].get("versionString"), "->", M["versionString"])
VER = ver["id"]

# Build
for attempt in range(40):
    d, _ = call("GET", f"/v1/builds?filter[app]={APP}&filter[version]={M['build']}&filter[preReleaseVersion.version]={M['versionString']}")
    b = d["data"][0] if d and d["data"] else None
    if b and b["attributes"].get("processingState") == "VALID":
        _, r = call("PATCH", f"/v1/appStoreVersions/{VER}/relationships/build", {"data": {"type": "builds", "id": b["id"]}})
        log("build", M["build"], "attached" if r.ok else "NOT attached"); break
    log("build", M["build"], "state", b and b["attributes"].get("processingState"), "- waiting")
    time.sleep(30)
else:
    log("!! build not ready; attach it later in App Store Connect")

# Review details
d, _ = call("GET", f"/v1/appStoreVersions/{VER}/appStoreReviewDetail", ok=(200,), quiet=True)
rd = {"notes": M["reviewNotes"], "demoAccountRequired": False}
for k, e in [("contactFirstName", "REVIEW_FIRST"), ("contactLastName", "REVIEW_LAST"), ("contactEmail", "REVIEW_EMAIL"), ("contactPhone", "REVIEW_PHONE")]:
    if os.environ.get(e): rd[k] = os.environ[e]
if d and d.get("data"):
    call("PATCH", f"/v1/appStoreReviewDetails/{d['data']['id']}", {"data": {"type": "appStoreReviewDetails", "id": d["data"]["id"], "attributes": rd}})
else:
    call("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": rd,
         "relationships": {"appStoreVersion": rel("appStoreVersions", VER)}}})
log("review notes set", "(contact: %s)" % ("yes" if "contactEmail" in rd else "missing"))

# App info: categories, age rating, subtitle, privacy URL
d, _ = call("GET", f"/v1/apps/{APP}/appInfos")
info = next((i for i in d["data"] if i["attributes"].get("appStoreState") != "READY_FOR_SALE" and i["attributes"].get("state") != "READY_FOR_DISTRIBUTION"), d["data"][0])
INFO = info["id"]
_, r = call("PATCH", f"/v1/appInfos/{INFO}", {"data": {"type": "appInfos", "id": INFO, "relationships": {
    "primaryCategory": rel("appCategories", M["primaryCategory"]), "secondaryCategory": rel("appCategories", M["secondaryCategory"])}}})
log("categories", M["primaryCategory"], M["secondaryCategory"], "ok" if r.ok else "failed")

d, _ = call("GET", f"/v1/appInfos/{INFO}/ageRatingDeclaration")
if d and d.get("data"):
    AR = d["data"]["id"]
    have = d["data"]["attributes"]
    a = {}
    for k, v in have.items():
        if k in ("kidsAgeBand", "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride", "developerAgeRatingInfoUrl"):
            continue
        a[k] = False if isinstance(v, bool) or k in ("gambling", "unrestrictedWebAccess", "lootBox", "messagingAndChat",
              "parentalControls", "ageAssurance", "userGeneratedContent", "healthOrWellnessTopics", "advertising", "seventeenPlus") else "NONE"
    for k in ("gambling", "unrestrictedWebAccess", "lootBox", "messagingAndChat", "parentalControls", "ageAssurance",
              "userGeneratedContent", "healthOrWellnessTopics", "advertising"):
        a.setdefault(k, False)
    for k in ("alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons", "horrorOrFearThemes",
              "matureOrSuggestiveThemes", "medicalOrTreatmentInformation", "profanityOrCrudeHumor", "sexualContentGraphicAndNudity",
              "sexualContentOrNudity", "violenceCartoonOrFantasy", "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic"):
        a.setdefault(k, "NONE")
    for _try in range(25):
        res, r = call("PATCH", f"/v1/ageRatingDeclarations/{AR}", {"data": {"type": "ageRatingDeclarations", "id": AR, "attributes": a}}, quiet=True)
        if res is not None: log("age rating set (all none)"); break
        try:
            errs = r.json()["errors"]
        except Exception:
            errs = []
        bad = [e.get("source", {}).get("pointer", "").split("/")[-1] for e in errs]
        bad = [b for b in bad if b in a]
        if not bad:
            log("!! age rating:", r.status_code, r.text[:600]); break
        for b in bad: a.pop(b, None)

d, _ = call("GET", f"/v1/appInfos/{INFO}/appInfoLocalizations")
infolocs = {l["attributes"]["locale"]: l for l in d["data"]}
for loc, L in M["localizations"].items():
    at = {"subtitle": L["subtitle"], "privacyPolicyUrl": L["privacyPolicyUrl"]}
    if loc in infolocs:
        _, r = call("PATCH", f"/v1/appInfoLocalizations/{infolocs[loc]['id']}", {"data": {"type": "appInfoLocalizations", "id": infolocs[loc]["id"], "attributes": at}})
    else:
        _, r = call("POST", "/v1/appInfoLocalizations", {"data": {"type": "appInfoLocalizations",
            "attributes": {"locale": loc, "name": app["attributes"]["name"], **at}, "relationships": {"appInfo": rel("appInfos", INFO)}}})
    log("app info", loc, "ok" if r.ok else "failed")

# Price: free
d, r = call("GET", f"/v1/apps/{APP}/appPriceSchedule", ok=(200,), quiet=True)
if not (d and d.get("data")):
    pts, _ = call("GET", f"/v1/apps/{APP}/appPricePoints?filter[territory]=USA&limit=200")
    free = next((p["id"] for p in pts["data"] if float(p["attributes"].get("customerPrice") or 0) == 0), None)
    _, r = call("POST", "/v1/appPriceSchedules", {"data": {"type": "appPriceSchedules", "relationships": {
        "app": rel("apps", APP), "baseTerritory": rel("territories", "USA"),
        "manualPrices": {"data": [{"type": "appPrices", "id": "${p0}"}]}}},
        "included": [{"type": "appPrices", "id": "${p0}", "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": rel("appPricePoints", free)}}]})
    log("price free", "ok" if r.ok else "failed")
else:
    log("price schedule exists")

# Availability: all territories
d, r = call("GET", f"/v1/apps/{APP}/appAvailabilityV2", ok=(200,), quiet=True)
if not (d and d.get("data")):
    ts, _ = call("GET", "/v1/territories?limit=200")
    ids = [t["id"] for t in ts["data"]]
    _, r = call("POST", "/v2/appAvailabilities", {"data": {"type": "appAvailabilities",
        "attributes": {"availableInNewTerritories": True}, "relationships": {"app": rel("apps", APP),
        "territoryAvailabilities": {"data": [{"type": "territoryAvailabilities", "id": "${t%s}" % t} for t in ids]}}},
        "included": [{"type": "territoryAvailabilities", "id": "${t%s}" % t, "attributes": {"available": True},
                      "relationships": {"territory": rel("territories", t)}} for t in ids]})
    log("availability", len(ids), "territories", "ok" if r.ok else "failed")
else:
    log("availability exists")

# Version localizations + screenshots
d, _ = call("GET", f"/v1/appStoreVersions/{VER}/appStoreVersionLocalizations")
vlocs = {l["attributes"]["locale"]: l["id"] for l in d["data"]}
for loc, L in M["localizations"].items():
    at = {k: L[k] for k in ("description", "keywords", "promotionalText", "supportUrl", "marketingUrl")}
    if loc in vlocs:
        _, r = call("PATCH", f"/v1/appStoreVersionLocalizations/{vlocs[loc]}", {"data": {"type": "appStoreVersionLocalizations", "id": vlocs[loc], "attributes": at}})
    else:
        res, r = call("POST", "/v1/appStoreVersionLocalizations", {"data": {"type": "appStoreVersionLocalizations",
            "attributes": {"locale": loc, **at}, "relationships": {"appStoreVersion": rel("appStoreVersions", VER)}}})
        if res: vlocs[loc] = res["data"]["id"]
    log("texts", loc, "ok" if r.ok else "failed")
    if loc not in vlocs: continue
    LID = vlocs[loc]
    sets, _ = call("GET", f"/v1/appStoreVersionLocalizations/{LID}/appScreenshotSets")
    sets = {s["attributes"]["screenshotDisplayType"]: s["id"] for s in sets["data"]}
    for tdir in sorted(glob.glob("appstore/screenshots/*")):
        kind = os.path.basename(tdir)
        files = sorted(glob.glob(f"{tdir}/{loc}/*.png") + glob.glob(f"{tdir}/{loc}/*.jpg"))
        if not files: continue
        if kind not in sets:
            res, _ = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": kind}, "relationships": {"appStoreVersionLocalization": rel("appStoreVersionLocalizations", LID)}}})
            if not res: continue
            sets[kind] = res["data"]["id"]
        SID = sets[kind]
        old, _ = call("GET", f"/v1/appScreenshotSets/{SID}/appScreenshots")
        for s in old["data"]:
            call("DELETE", f"/v1/appScreenshots/{s['id']}")
        n = 0
        for f in files:
            data = open(f, "rb").read()
            res, _ = call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots",
                "attributes": {"fileName": os.path.basename(f), "fileSize": len(data)},
                "relationships": {"appScreenshotSet": rel("appScreenshotSets", SID)}}})
            if not res: continue
            sh = res["data"]
            for op in sh["attributes"]["uploadOperations"]:
                h = {x["name"]: x["value"] for x in op.get("requestHeaders", [])}
                requests.request(op["method"], op["url"], headers=h, data=data[op["offset"]:op["offset"] + op["length"]], timeout=120).raise_for_status()
            res, _ = call("PATCH", f"/v1/appScreenshots/{sh['id']}", {"data": {"type": "appScreenshots", "id": sh["id"],
                "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
            if res: n += 1
        log("screenshots", loc, kind, f"{n}/{len(files)}")

time.sleep(20)
# Final check of screenshot processing
for loc, LID in vlocs.items():
    sets, _ = call("GET", f"/v1/appStoreVersionLocalizations/{LID}/appScreenshotSets?include=appScreenshots")
    for s in (sets or {}).get("included", []):
        st = s["attributes"].get("assetDeliveryState") or {}
        if st.get("state") not in ("COMPLETE", "UPLOAD_COMPLETE"):
            log("screenshot", loc, s["attributes"].get("fileName"), st)
open("appstore/report.txt", "w").write("\n".join(report) + "\n")

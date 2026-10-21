import os, time, json, jwt, requests
KEY_ID, ISSUER, P8 = os.environ["KEY_ID"], os.environ["ISSUER_ID"], os.environ["P8"]
now = int(time.time())
tok = jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"}, P8, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
H = {"Authorization": "Bearer " + tok}
out = []
def g(p):
    r = requests.get("https://api.appstoreconnect.apple.com" + p, headers=H, timeout=60)
    if not r.ok: out.append(f"!! {p} {r.status_code} {r.text[:300]}"); return {"data": []}
    return r.json()
apps = g("/v1/apps?limit=50")["data"]
for a in apps:
    out.append(f"APP {a['id']} {a['attributes']['name']} {a['attributes']['bundleId']} {a['attributes'].get('primaryLocale')}")
    for v in g(f"/v1/apps/{a['id']}/appStoreVersions?limit=20")["data"]:
        at = v["attributes"]
        out.append(f"  VERSION {v['id']} {at.get('platform')} {at.get('versionString')} {at.get('appStoreState')} {at.get('appVersionState')}")
        for l in g(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]:
            la = l["attributes"]
            out.append(f"    LOC {la['locale']} desc={len(la.get('description') or '')} kw={len(la.get('keywords') or '')} promo={len(la.get('promotionalText') or '')}")
            sets = g(f"/v1/appStoreVersionLocalizations/{l['id']}/appScreenshotSets?include=appScreenshots&limit=50")
            inc = {s["id"]: s for s in sets.get("included", [])}
            for s in sets["data"]:
                ids = [x["id"] for x in s.get("relationships", {}).get("appScreenshots", {}).get("data", [])]
                states = [ (inc.get(i, {}).get("attributes", {}).get("assetDeliveryState") or {}).get("state") for i in ids]
                out.append(f"      SET {s['attributes']['screenshotDisplayType']} n={len(ids)} {states}")
    for i in g(f"/v1/apps/{a['id']}/appInfos")["data"]:
        out.append(f"  APPINFO {i['id']} {i['attributes'].get('appStoreState')} {i['attributes'].get('state')}")
        for l in g(f"/v1/appInfos/{i['id']}/appInfoLocalizations")["data"]:
            la = l["attributes"]; out.append(f"    INFOLOC {la['locale']} name={la.get('name')!r} subtitle={la.get('subtitle')!r} privacy={la.get('privacyPolicyUrl')!r}")
open("check.txt", "w").write("\n".join(out) + "\n"); print("\n".join(out))

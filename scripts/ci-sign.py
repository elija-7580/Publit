#!/usr/bin/env python3
"""Signs an unsigned Publit archive for the App Store and packs the IPA.

Why not Xcode's export: the account name contains a non-ASCII letter (Á). codesign writes it
into the designated requirement in a decomposed Unicode form, and App Store Connect then
rejects every binary ("Code failed to satisfy specified code requirement(s)", ITMS-90035).
Here each bundle gets an explicit designated requirement that names the team, not the
certificate's common name.

Usage: ci-sign.py <Publit.app> <profiles dir> <identity SHA-1> <out.ipa>
Profiles dir: app/widgets/watch/share .mobileprovision.
"""
import os, plistlib, shutil, subprocess, sys, tempfile

TEAM = "3D6S8GFSGK"
app, profiles, identity, out = sys.argv[1:5]

def profile(name):
    path = os.path.join(profiles, name + ".mobileprovision")
    raw = subprocess.run(["security", "cms", "-D", "-i", path], check=True, capture_output=True).stdout
    return path, plistlib.loads(raw)

def entitlements(prof, extra):
    e = prof["Entitlements"]
    ent = {k: e[k] for k in ("application-identifier", "com.apple.developer.team-identifier", "beta-reports-active") if k in e}
    ent["get-task-allow"] = False
    ent.update(extra)
    return ent

# The certificate's common name, precomposed (NFC) exactly as in the certificate: "Á" is c3 81.
CN_NFC = "Apple Distribution: ELIU\u00c1 SAMUEL I. FRIEDRICH-ULRICH (3D6S8GFSGK)".encode()
CN_ASCII = "Apple Distribution: ELIU@@ SAMUEL I. FRIEDRICH-ULRICH (3D6S8GFSGK)".encode()
assert len(CN_NFC) == len(CN_ASCII)

def requirement(bid):
    """Xcode's usual designated requirement, compiled with an ASCII stand-in of the same byte
    length, then patched to the precomposed name (csreq/codesign would store it decomposed)."""
    work = tempfile.mkdtemp()
    text = os.path.join(work, "req.txt")
    blob = os.path.join(work, "req.bin")
    with open(text, "w") as f:
        f.write('designated => identifier "%s" and anchor apple generic and certificate leaf[subject.CN] = "%s" '
                'and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */\n' % (bid, CN_ASCII.decode()))
    subprocess.run(["csreq", "-r", text, "-b", blob], check=True)
    data = open(blob, "rb").read()
    assert data.count(CN_ASCII) == 1, "placeholder not found once"
    open(blob, "wb").write(data.replace(CN_ASCII, CN_NFC))
    return blob

def sign(bundle, name, extra=None):
    path, prof = profile(name)
    shutil.copy(path, os.path.join(bundle, "embedded.mobileprovision"))
    with open(os.path.join(bundle, "Info.plist"), "rb") as f:
        bid = plistlib.load(f)["CFBundleIdentifier"]
    ent = entitlements(prof, extra or {})
    assert ent["application-identifier"] == f"{TEAM}.{bid}", (ent["application-identifier"], bid)
    req = requirement(bid)
    # Nested code first: frameworks and loose dylibs inside this bundle.
    fw = os.path.join(bundle, "Frameworks")
    if os.path.isdir(fw):
        for item in sorted(os.listdir(fw)):
            if item.endswith((".framework", ".dylib")):
                subprocess.run(["codesign", "-f", "-s", identity, "--timestamp", os.path.join(fw, item)], check=True)
    with tempfile.NamedTemporaryFile(suffix=".plist", delete=False) as t:
        plistlib.dump(ent, t)
    subprocess.run(["codesign", "-f", "-s", identity, "--timestamp", "--generate-entitlement-der",
                    "--entitlements", t.name, "--requirements", req, bundle], check=True)
    subprocess.run(["codesign", "--verify", "--strict", bundle], check=True)
    print(f"signed {bid}: {sorted(ent)}")

for w in sorted(os.listdir(os.path.join(app, "Watch"))) if os.path.isdir(os.path.join(app, "Watch")) else []:
    sign(os.path.join(app, "Watch", w), "watch")
plugins = os.path.join(app, "PlugIns")
for p in sorted(os.listdir(plugins)) if os.path.isdir(plugins) else []:
    sign(os.path.join(plugins, p), "share" if "Share" in p else "widgets")
sign(app, "app", {"com.apple.developer.healthkit": True, "com.apple.developer.healthkit.access": []})

work = tempfile.mkdtemp()
os.makedirs(os.path.join(work, "Payload"))
subprocess.run(["ditto", app, os.path.join(work, "Payload", os.path.basename(app))], check=True)
subprocess.run(["bash", "-c", f'cd "{work}" && zip -qry "{os.path.abspath(out)}" Payload'], check=True)
print("ipa", out)

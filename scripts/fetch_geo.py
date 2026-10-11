"""Bundle geoip/geosite from the pinned official Xray release, with SHA-256 verification."""
import hashlib
import urllib.request
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
archive = root / "build" / "xray-geo-release.zip"
archive.parent.mkdir(exist_ok=True)
url = "https://github.com/XTLS/Xray-core/releases/download/v26.9.30/Xray-macos-arm64-v8a.zip"
expected = "4b363bd924df5bf09f87bd445755ff8e5742b9a8a0480cda261061416c3c7dce"
if not archive.exists():
    urllib.request.urlretrieve(url, archive)
if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
    raise SystemExit("Official Xray release checksum mismatch")
resources = root / "Tunnel" / "Resources"
resources.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(archive) as bundle:
    for name in ["geoip.dat", "geosite.dat"]:
        path = next(item for item in bundle.namelist() if item.endswith(name))
        (resources / name).write_bytes(bundle.read(path))
print("Verified official geoip/geosite assets for Xray 26.9.30")

"""Boot an available iPhone, launch the unsigned simulator app and take a real UI screenshot."""
import json
import pathlib
import subprocess
import time

def run(*args):
    return subprocess.check_output(args, text=True).strip()

available = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json"))
devices = [device for runtime, items in available["devices"].items() if "iOS" in runtime
           for device in items if device["name"].startswith("iPhone")]
if not devices:
    raise SystemExit("No available iOS simulator runtime; cannot validate UI launch")
device = next((item for item in devices if item["state"] == "Booted"), devices[0])
udid = device["udid"]
if device["state"] != "Booted":
    run("xcrun", "simctl", "boot", udid)
run("xcrun", "simctl", "bootstatus", udid, "-b")
run("xcrun", "simctl", "ui", udid, "appearance", "dark")
run("xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100")
app = "build/simulator/Build/Products/Debug-iphonesimulator/BahaVPN.app"
run("xcrun", "simctl", "install", udid, app)
launched = run("xcrun", "simctl", "launch", udid, "com.kittenello.bahavpn", "--preview-data")
print(launched)
time.sleep(8)
# Fail if the app exited, rather than saving a home-screen picture as a successful preview.
pid = launched.rsplit(":", 1)[-1].strip()
run("kill", "-0", pid)
pathlib.Path("build").mkdir(exist_ok=True)
run("xcrun", "simctl", "io", udid, "screenshot", "build/preview.png")
print("Simulator app launched; preview includes clearly marked demo profiles, not a live VPN connection.")

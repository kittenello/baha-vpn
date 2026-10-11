"""Build the full pinned Xray core as one Go runtime per Network Extension process."""
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
native = root / "Native"
output = root / "build" / "native"
output.mkdir(parents=True, exist_ok=True)

def run(*args, env=None):
    subprocess.run(args, cwd=native, env=env, check=True)

run("go", "mod", "tidy")
fixture_env = dict(os.environ)
if (root / "build" / "fixtures").exists():
    fixture_env["BAHA_FIXTURES"] = str(root / "build" / "fixtures")
run("go", "test", "-v", "./engine", env=fixture_env)
variants = [("iphoneos", "arm64", "arm64-apple-ios17.0"),
            ("iphonesimulator", "arm64", "arm64-apple-ios17.0-simulator")]
framework = native / "XrayNative.xcframework"
if framework.exists():
    print("using cached native framework")
    raise SystemExit(0)
libraries = []
for sdk, arch, target in variants:
    directory = output / (sdk + "-" + arch)
    directory.mkdir(exist_ok=True)
    sdk_path = subprocess.check_output(["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True).strip()
    flags = "-isysroot " + sdk_path + " -target " + target
    env = dict(os.environ, GOOS="ios", GOARCH=arch, CGO_ENABLED="1", CC="xcrun --sdk " + sdk + " clang",
               CGO_CFLAGS=flags, CGO_LDFLAGS=flags)
    library = directory / "libbaha.a"
    run("go", "build", "-trimpath", "-ldflags=-s -w", "-buildmode=c-archive", "-o", str(library), ".", env=env)
    (directory / "module.modulemap").write_text('module XrayNative { header "libbaha.h" export * }\n')
    libraries += ["-library", str(library), "-headers", str(directory)]
run("xcodebuild", "-create-xcframework", *libraries, "-output", str(framework))

"""Verify existing split APKs and prepare a versioned Clustter release directory."""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path


def run(args, env):
    completed = subprocess.run([str(a) for a in args], env=env, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if completed.returncode:
        raise RuntimeError(f"Android verification failed: {Path(args[0]).name}")
    return completed.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("--name", required=True)
    parser.add_argument("--sdk", type=Path, required=True)
    parser.add_argument("--java-home", type=Path, required=True)
    parser.add_argument("--certificate", default="ffe345ae284d16df6e57a7fa3646210f4cad3a52282a215aaed67c86aece1d76")
    args = parser.parse_args()
    root = args.project.resolve()
    pubspec = (root / "pubspec.yaml").read_text(encoding="utf-8")
    version, build = re.search(r"(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", pubspec).groups()
    app_id = re.search(r'applicationId\s*=\s*"([^"]+)"', (root / "android/app/build.gradle.kts").read_text(encoding="utf-8"))[1]
    env = dict(os.environ, JAVA_HOME=str(args.java_home))
    tools = args.sdk / "build-tools/36.1.0"
    validated = []
    for abi, offset in [("arm64-v8a", 2), ("armeabi-v7a", 1), ("x86_64", 4)]:
        source = root / f"build/app/outputs/flutter-apk/app-{abi}-release.apk"
        badging = run([tools / "aapt.exe", "dump", "badging", source], env)
        package = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging)
        if not package or package.groups() != (app_id, str(offset * 1000 + int(build)), version):
            raise ValueError(f"Stale/wrong APK metadata: {abi}")
        if "application-debuggable" in badging or f"native-code: '{abi}'" not in badging:
            raise ValueError(f"Unexpected debug/ABI: {abi}")
        permissions = run([tools / "aapt.exe", "dump", "permissions", source], env)
        if "uses-permission: name='android.permission.INTERNET'" not in permissions:
            raise ValueError(f"Update requires INTERNET in the release APK: {abi}")
        certs = run([tools / "apksigner.bat", "verify", "--print-certs", source], env)
        actual = re.search(r"Signer #1 certificate SHA-256 digest:\s*([a-f0-9]+)", certs)
        if not actual or actual[1] != args.certificate:
            raise ValueError(f"Original certificate mismatch: {abi}")
        run([tools / "zipalign.exe", "-c", "-P", "16", "4", source], env)
        validated.append((abi, source))
    destination = root / f"dist/{version}"
    destination.mkdir(parents=True, exist_ok=True)
    results = []
    for abi, source in validated:
        target = destination / f"{args.name}-{version}-{abi}.apk"
        shutil.copy2(source, target)
        results.append({"file": target.name, "bytes": target.stat().st_size,
            "sha256": hashlib.sha256(target.read_bytes()).hexdigest(), "abi": abi})
    result = {"version": version, "baseBuild": int(build), "package": app_id,
        "certificate": args.certificate, "internetPermission": True,
        "verified": True, "assets": results}
    (destination / "android.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result))


if __name__ == "__main__":
    main()

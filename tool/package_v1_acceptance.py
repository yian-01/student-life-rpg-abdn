"""Package the frozen V1.0 CI artifacts without rebuilding or re-signing them."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
from zipfile import ZipFile


SOURCE = "29b1bebb208fc3f2d0fd6cfe684e280eba0f7583"
RUN = 43169002569
ARTIFACTS = {
    "windows": (13921134161, "59e4db9fd2814eb43a1f5645cde58e1ea8a2c217adb11124962cb10841b7cb5d"),
    "android": (13922145173, "01fc47b622c00db48729446b7cefd719fcc7910a6e25b69f400b364497659363"),
}


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def checked_archive(path, expected):
    if sha256(path) != expected:
        raise ValueError(f"Artifact checksum differs from GitHub: {path.name}")
    with ZipFile(path) as archive:
        for info in archive.infolist():
            name = info.filename
            relative = PurePosixPath(name)
            if relative.is_absolute() or ".." in relative.parts or "\\" in name or ":" in name:
                raise ValueError("Unsafe artifact entry")
            if (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError("Symlink artifact entry")
        if archive.testzip() is not None:
            raise ValueError("Corrupt ZIP")
        return archive.namelist()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--windows-zip", type=Path, required=True)
    parser.add_argument("--android-zip", type=Path, required=True)
    parser.add_argument("--test-log", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    tests = args.test_log.read_text(encoding="utf-8-sig")
    if "+739: All tests passed!" not in tests or "[E]" in tests:
        raise ValueError("Expected the complete passing V1.0 regression log")
    members = {}
    for platform in ARTIFACTS:
        path = getattr(args, platform + "_zip")
        members[platform] = checked_archive(path, ARTIFACTS[platform][1])
    required = {"student_life_rpg.exe", "flutter_windows.dll", "flutter_inappwebview_windows_plugin.dll", "WebView2Loader.dll"}
    if not required.issubset(members["windows"]):
        raise ValueError("Windows artifact is missing runtime dependencies")
    if not any(name.startswith("data/") for name in members["windows"]):
        raise ValueError("Windows artifact is missing its data directory")
    apks = [name for name in members["android"] if name.endswith(".apk")]
    if len(apks) != 1:
        raise ValueError("Expected exactly one APK")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    windows = output / "Student-Life-RPG-1.0.0-Windows-x64.zip"
    android = output / "Student-Life-RPG-1.0.0-Android-acceptance.apk"
    # Deliberately refuse to replace an existing deliverable.
    for path in (windows, android, output / "manifest.json", output / "SHA256SUMS.txt"):
        if path.exists():
            raise FileExistsError(path)
    shutil.copyfile(args.windows_zip, windows)
    with ZipFile(args.android_zip) as archive, archive.open(apks[0]) as src, android.open("xb") as dst:
        shutil.copyfileobj(src, dst)
    files = [{"name": p.name, "bytes": p.stat().st_size, "sha256": sha256(p)} for p in (windows, android)]
    manifest = {
        "version": "1.0.0+1",
        "status": "acceptance-candidate-not-a-stable-release",
        "source_commit": SOURCE,
        "workflow_run": RUN,
        "source_url": f"https://github.com/yian-01/student-life-rpg-abdn/commit/{SOURCE}",
        "artifacts": {p: {"id": v[0], "archive_sha256": v[1]} for p, v in ARTIFACTS.items()},
        "local_regression": {"passed": 739, "failed": 0, "log_sha256": sha256(args.test_log)},
        "android_signing": "Original CI Android Debug signing, not a production signing key",
        "files": files,
        "pending": ["physical-device acceptance", "old-installation upgrade and cross-device backup restore", "SCNU login", "review and approved merge/release"],
    }
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "SHA256SUMS.txt").write_text("".join(f"{p['sha256']}  {p['name']}\n" for p in files), encoding="utf-8")
    print(json.dumps({"output": str(output), "source_commit": SOURCE, "files": files}, ensure_ascii=True))


if __name__ == "__main__":
    main()

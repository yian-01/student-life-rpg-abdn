#!/usr/bin/env bash
# The release workflow fills these placeholders in the published script.
set -euo pipefail
release_tag='@RELEASE_TAG@'
expected_sha='@SHA256@'
backend=/home/admin/keyulife/backend
if [[ ! "$release_tag" =~ ^keyulife-interface-[a-f0-9]{12}$ || ! "$expected_sha" =~ ^[a-f0-9]{64}$ ]]; then
  echo 'Use the update-interface.sh asset from the verified interface release.' >&2
  exit 1
fi
cd "$backend"
test -f .env && test -d site
exec 9>.interface-update.lock
flock -n 9 || { echo 'An interface update is already running.' >&2; exit 1; }
work=$(mktemp -d "$backend/.interface-update.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
curl -fL --retry 3 --connect-timeout 20 \
  "https://github.com/yian-01/student-life-rpg-abdn/releases/download/$release_tag/keyulife-interface.zip" \
  -o "$work/interface.zip"
printf '%s  %s\n' "$expected_sha" "$work/interface.zip" | sha256sum -c -
python3 - "$work/interface.zip" "$work/site" <<'PY'
import pathlib, stat, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as bundle:
    required = {'index.html', 'main.dart.js', 'flutter_bootstrap.js', 'student_life_browser.js'}
    if not required.issubset(set(bundle.namelist())):
        raise SystemExit('Incomplete web bundle; current website has not changed.')
    for item in bundle.infolist():
        path = pathlib.PurePosixPath(item.filename)
        if path.is_absolute() or '..' in path.parts or stat.S_ISLNK(item.external_attr >> 16):
            raise SystemExit('Unsafe bundle path')
    bundle.extractall(sys.argv[2])
PY
backup="site.before-$(date +%Y%m%d-%H%M%S)-$$"
mv site "$backup"
if ! mv "$work/site" site; then
  mv "$backup" site
  exit 1
fi
restore() {
  mv site "$work/failed-site"
  mv "$backup" site
  sudo docker compose up -d --no-deps --force-recreate https
  echo 'Update failed. The previous interface has been restored.' >&2
}
if ! sudo docker compose up -d --no-deps --force-recreate https; then
  restore
  exit 1
fi
for attempt in {1..20}; do
  if curl -fsS --max-time 5 https://keyulife.cn/healthz | python3 -c 'import json,sys; assert json.load(sys.stdin).get("ok") is True'; then
    echo "Interface updated. Previous files: $backend/$backup"
    echo 'Open https://keyulife.cn/ and refresh. Your backend, account data and .env were preserved.'
    exit 0
  fi
  sleep 2
done
restore
exit 1

#!/usr/bin/env bash
set -euo pipefail

KEYULIFE_ROOT=/home/admin/keyulife
KEYULIFE_ARCHIVE=/home/admin/keyulife-deploy.zip
KEYULIFE_RELEASE=https://github.com/yian-01/student-life-rpg-abdn/releases/download/keyulife-v1.1-deploy/keyulife-deploy.zip
KEYULIFE_SHA256=e6e9062c6ba7f46e8e2ee3dbae18447b353a560b16689d348748fe29e957fc5a

sudo docker compose version
mkdir -p "$KEYULIFE_ROOT"
curl -fL --retry 3 --connect-timeout 20 "$KEYULIFE_RELEASE" -o "$KEYULIFE_ARCHIVE"
printf '%s  %s\n' "$KEYULIFE_SHA256" "$KEYULIFE_ARCHIVE" | sha256sum -c -
unzip -oq "$KEYULIFE_ARCHIVE" -d "$KEYULIFE_ROOT"
cd "$KEYULIFE_ROOT/backend"

# The pinned legacy archive required an invitation in Compose. Allow the
# current public-registration default without rebuilding or replacing data.
python3 - <<'PUBLIC_REGISTRATION'
from pathlib import Path
path = Path('compose.yaml')
text = path.read_text()
text = text.replace('${SYNC_SIGNUP_CODE:?Set a registration code in backend/.env}',
                    '${SYNC_SIGNUP_CODE:-}')
path.write_text(text)
PUBLIC_REGISTRATION

if [ ! -f .env ]; then
  umask 077
  printf 'COMPOSE_PROJECT_NAME=keyulife\nSYNC_DOMAIN=keyulife.cn\nSYNC_SIGNUP_CODE=\n' > .env
fi

sudo docker compose up -d --build api
sudo docker compose exec -T api python - <<'CHECK_BACKEND'
import time
import urllib.request

for attempt in range(30):
    try:
        response = urllib.request.urlopen(
            'http://127.0.0.1:8080/healthz', timeout=5
        )
        print(response.read().decode())
        break
    except OSError:
        time.sleep(1)
else:
    raise SystemExit('Backend health check failed')
CHECK_BACKEND

sudo docker compose ps

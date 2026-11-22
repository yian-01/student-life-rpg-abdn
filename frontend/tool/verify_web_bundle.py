"""Reject incomplete Flutter artifacts before upload or deployment."""
import argparse
import hashlib
import json
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit


class Scripts(HTMLParser):
    def __init__(self):
        super().__init__()
        self.paths = []

    def handle_starttag(self, tag, attrs):
        if tag == 'script':
            src = dict(attrs).get('src')
            if src:
                self.paths.append(src)


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('root', type=Path)
parser.add_argument('--reject-test-api', action='store_true')
args = parser.parse_args()
root = args.root.resolve(strict=True)
required = {
    'index.html', 'main.dart.js', 'flutter_bootstrap.js', 'flutter.js',
    'student_life_browser.js', 'garden_audio.js', 'assets/FontManifest.json',
    'assets/assets/garden/plants.json', 'assets/assets/garden/blossom.png',
    'assets/assets/fonts/GardenSerif-Regular.ttf',
    'assets/assets/garden/PROVENANCE.txt', 'assets/NOTICES',
    'canvaskit/canvaskit.wasm',
}
index = root / 'index.html'
if not index.is_file():
    raise SystemExit('Incomplete bundle: index.html is absent')
scripts = Scripts()
scripts.feed(index.read_text(encoding='utf-8'))
for src in scripts.paths:
    url = urlsplit(src)
    if not url.scheme and not url.netloc:
        required.add(url.path.lstrip('/'))
missing = [name for name in sorted(required)
           if not (root / name).is_file() or (root / name).stat().st_size == 0]
if missing:
    raise SystemExit('Incomplete bundle: ' + ', '.join(missing))
if args.reject_test_api and b'https://127.0.0.1:18444' in (root / 'main.dart.js').read_bytes():
    raise SystemExit('Refusing a deployment bundle containing the test API origin')
files = [file for file in sorted(root.rglob('*')) if file.is_file()]
manifest = {
    str(file.relative_to(root)).replace('\\', '/'):
        hashlib.sha256(file.read_bytes()).hexdigest()
    for file in files
}
print(json.dumps({'verified': len(files), 'sha256': manifest}, indent=2))

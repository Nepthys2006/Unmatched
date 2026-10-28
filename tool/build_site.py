"""Assembles the Netlify site: the landing page at / and the web game at /play/.

    flutter build web --release --base-href /play/ --output build/web_play
    python tool/build_site.py              -> build/site  (drag this folder onto Netlify, or `netlify deploy --prod --dir build/site`)

The landing page source lives in ../landing (index.html, site.css, site.js, heroes.json, img/).
"""
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LANDING = ROOT.parent / 'landing'
GAME = ROOT / 'build' / 'web_play'
OUT = ROOT / 'build' / 'site'

NETLIFY_TOML = """# Unmatched, fan edition: landing page at /, the Flutter web game at /play/.
[build]
  publish = "."

# The game's engine files need the right type, and CanvasKit must be allowed to stream.
[[headers]]
  for = "/play/*.wasm"
  [headers.values]
    Content-Type = "application/wasm"
[[headers]]
  for = "/play/canvaskit/*"
  [headers.values]
    Cache-Control = "public, max-age=31536000, immutable"
[[headers]]
  for = "/play/assets/*"
  [headers.values]
    Cache-Control = "public, max-age=86400"
# Always check for a new build of the game and the page itself.
[[headers]]
  for = "/play/index.html"
  [headers.values]
    Cache-Control = "no-cache"
[[headers]]
  for = "/play/main.dart.js"
  [headers.values]
    Cache-Control = "no-cache"
[[headers]]
  for = "/play/flutter_bootstrap.js"
  [headers.values]
    Cache-Control = "no-cache"

[[redirects]]
  from = "/play"
  to = "/play/"
  status = 301
[[redirects]]
  from = "/play/*"
  to = "/play/index.html"
  status = 200
"""


def main():
    if not (GAME / 'index.html').exists():
        raise SystemExit('Build the game first: flutter build web --release --base-href /play/ --output build/web_play')
    if OUT.exists():
        shutil.rmtree(OUT)
    shutil.copytree(LANDING, OUT, ignore=shutil.ignore_patterns('.taste-skill', 'play'))
    shutil.copytree(GAME, OUT / 'play', ignore=shutil.ignore_patterns('.last_build_id'))
    # The LAN web runtime ships inside the apps only; the website doesn't need it.
    shutil.rmtree(OUT / 'play' / 'assets' / 'assets' / 'webapp', ignore_errors=True)
    (OUT / 'netlify.toml').write_text(NETLIFY_TOML, encoding='utf-8')
    size = sum(f.stat().st_size for f in OUT.rglob('*') if f.is_file())
    print(f'site: {size / 1e6:.0f} MB in {OUT.relative_to(ROOT)}')


if __name__ == '__main__':
    main()

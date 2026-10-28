"""Puts the web build's runtime into the app, so a LAN host (phone or PC) can serve the game to
browsers on the same network: they open http://<host address>:47400 and join from there.

Only the runtime is copied (index.html, main.dart.js, CanvasKit, fonts, shaders, manifests); the
game's art and data are served from the host app's own bundle.

    flutter build web --release --no-web-resources-cdn --output build/web_lan
    python tool/bundle_webapp.py
    flutter build apk --release      (or windows)
"""
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'build' / 'web_lan'
OUT = ROOT / 'assets' / 'webapp'

KEEP = [
    'index.html', 'main.dart.js', 'flutter.js', 'flutter_bootstrap.js', 'manifest.json', 'favicon.png', 'version.json',
    'icons/Icon-192.png', 'icons/Icon-512.png',
    'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm',
    'canvaskit/chromium/canvaskit.js', 'canvaskit/chromium/canvaskit.wasm',
    'assets/AssetManifest.bin', 'assets/AssetManifest.bin.json', 'assets/FontManifest.json', 'assets/NOTICES',
    'assets/fonts/MaterialIcons-Regular.otf', 'assets/fonts/fallback/Roboto-Regular.ttf',
    'assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
    'assets/shaders/ink_sparkle.frag', 'assets/shaders/stretch_effect.frag',
]


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    total = 0
    for rel in KEEP:
        src = SRC / rel
        if not src.exists():
            print('missing (skipped):', rel)
            continue
        dest = OUT / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dest)
        total += dest.stat().st_size
    # Ensure all directories declared in pubspec.yaml exist even if skipped
    fallback_dir = OUT / 'assets' / 'fonts' / 'fallback'
    fallback_dir.mkdir(parents=True, exist_ok=True)
    (fallback_dir / '.keep').touch(exist_ok=True)
    print(f'web runtime: {total / 1e6:.1f} MB in {OUT.relative_to(ROOT)}')


if __name__ == '__main__':
    main()

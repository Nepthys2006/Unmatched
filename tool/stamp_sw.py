"""Gives each web build its own offline-cache name, so a new release replaces the old cache.

    python tool/stamp_sw.py build/web build/web_play

web/sw.js keeps the placeholder __BUILD__ in its cache name; this swaps it for the build time in the
copies inside the given build folders. Without it a returning player could keep an old engine.
"""
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main(folders):
    stamp = time.strftime('%Y%m%d%H%M%S')
    for name in folders:
        sw = ROOT / name / 'sw.js'
        if not sw.exists():
            raise SystemExit(f'{sw} is missing: build the web app first.')
        text = sw.read_text(encoding='utf-8')
        if '__BUILD__' not in text:
            raise SystemExit(f'{sw} has no __BUILD__ placeholder (already stamped, or an old sw.js).')
        sw.write_bytes(text.replace('__BUILD__', stamp).encode('utf-8'))
        print(f'{name}/sw.js stamped {stamp}')


if __name__ == '__main__':
    main(sys.argv[1:] or ['build/web'])

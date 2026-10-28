"""Copies the battlefield maps into the game: assets/data/maps.json and assets/maps/<id>.webp.

Sources:
  ../Map Viewer/glb/final.json    the 32 printed Unmatched maps (built and checked by
                                  `python tools/finalize.py` in the Map Viewer folder)
  tool/maps_custom/<id>.json      the game's own maps, drawn in the same style by
                                  tool/draw_maps.py (art in tool/maps_custom/<id>.png)

    python tool/build_maps.py
"""
import json
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent.parent
VIEWER = HERE.parent / 'Map Viewer'
CUSTOM = HERE / 'tool' / 'maps_custom'
OUT_ART = HERE / 'assets' / 'maps'
OUT_JSON = HERE / 'assets' / 'data' / 'maps.json'


def save_art(src: Path, dest: Path, max_w=2048):
    im = Image.open(src).convert('RGB')
    if im.width > max_w:
        im = im.resize((max_w, round(im.height * max_w / im.width)), Image.LANCZOS)
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.save(dest, 'WEBP', quality=86, method=6)
    return im.size


def main():
    maps = {}
    final = json.loads((VIEWER / 'glb' / 'final.json').read_text(encoding='utf-8'))
    art_src = {p.stem: p for p in (VIEWER / 'maps').iterdir()}
    for key, m in final.items():
        w, h = save_art(art_src[key], OUT_ART / f'{key}.webp')
        scale = w / m['art']['w']
        maps[key] = {
            'id': key,
            'name': m['name'],
            'modes': m['modes'],
            'set': m['set'],
            'theme': 'printed',
            'blurb': f"From Unmatched: {m['set']}." if m['set'] else '',
            'zones': m['zones'],
            'spaces': m['spaces'],
            'links': m['links'],
            'oneway': m['oneway'],
            'stairs': m['stairs'],
            'art': {'file': f'{key}.webp', 'w': w, 'h': h, 'unitPx': round(m['art']['unitPx'] * scale, 3)},
        }
    if CUSTOM.exists():
        for f in sorted(p for p in CUSTOM.glob('*.json') if p.stem != 'old_layouts'):
            m = json.loads(f.read_text(encoding='utf-8'))
            w, h = save_art(f.with_suffix('.png'), OUT_ART / f"{m['id']}.webp")
            m['art'] = {'file': f"{m['id']}.webp", 'w': w, 'h': h, 'unitPx': m['art']['unitPx'] * w / m['art']['w']}
            maps[m['id']] = m
    OUT_JSON.write_text(json.dumps(maps, indent=1), encoding='utf-8')
    by_mode = {}
    for m in maps.values():
        for mode in m['modes']:
            by_mode.setdefault(mode, []).append(m['id'])
    print(f'{len(maps)} maps:', {k: len(v) for k, v in by_mode.items()})
    used = {f"{m['id']}.webp" for m in maps.values()}
    for old in OUT_ART.glob('*.webp'):
        if old.name not in used:
            old.unlink()


if __name__ == '__main__':
    main()

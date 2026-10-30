"""Copies the 3D board's hero figures into the app.

Reads the cropped miniature renders from the Map Viewer (../Map Viewer/minis, made by its
tools/make_minis.py) and writes, for every hero in assets/heroes:

    assets/heroes/<id>/figure[-n].webp   the figure, cut off its printed base
    assets/web3d/figures.json            {hero id: [{file, w, h, baseW, baseX}, ...]}

A hero's list is in fighter order: a hero with several hero fighters (the three Raptors, Cloak and
Dagger) gets one figure each, and the board picks by the fighter's index.

    python tool/make_figures.py        (needs Pillow)
"""
import json
import os

from PIL import Image

import sprite_edges  # keeps the colour under the cut-out's transparent edge (no black outline)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MINIS = os.path.join(os.path.dirname(ROOT), 'Map Viewer')
HEROES = os.path.join(ROOT, 'assets', 'heroes')

# miniature file order differs from fighter order for these heroes
ORDER = {'cloak-dagger': ['cloak-dagger-2', 'cloak-dagger']}


def webp(src, dest):
    sprite_edges.save_webp(Image.open(src), dest, quality=86)


def main():
    minis = json.load(open(os.path.join(MINIS, 'minis.json'), encoding='utf8'))
    by_hero = {}
    for m in minis:
        if m['kind'] == 'hero':
            by_hero.setdefault(m['hero'], []).append(m)
    out = {}
    for hero in sorted(os.listdir(HEROES)):
        figs = by_hero.get(hero)
        if not figs:
            print('no figure for', hero)
            continue
        # the main render first, then "Miniature 2", "Miniature 3"
        figs.sort(key=lambda m: (m['id'] != hero, m['id']))
        if hero in ORDER:
            figs.sort(key=lambda m: ORDER[hero].index(m['id']))
        out[hero] = []
        for i, m in enumerate(figs):
            name = 'figure' + (f'-{i + 1}' if i else '')
            webp(os.path.join(MINIS, m['file']), os.path.join(HEROES, hero, name + '.webp'))
            out[hero].append(dict(file=f'../heroes/{hero}/{name}.webp', w=m['w'], h=m['h'], baseW=m['baseW'], baseX=m['baseX']))
    path = os.path.join(ROOT, 'assets', 'web3d', 'figures.json')
    json.dump(out, open(path, 'w', encoding='utf8'), separators=(',', ':'))
    print(len(out), 'heroes,', sum(len(v) for v in out.values()), 'figures')


if __name__ == '__main__':
    main()

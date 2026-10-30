"""Black-outline fix for cut-out sprites (miniatures, figures, sidekick tokens).

The cut-outs sit on a transparent ground whose colour is black (rgb 0,0,0 under alpha 0), and the
WebP encoder drops the colour under transparent pixels unless told to keep it. Any filtering that is
not premultiplied (WebGL on phones and tablets, the browser's mip-maps, Safari) then blends that
black into the edge and the hero shows a dark outline.

`bleed()` repaints every transparent / soft-edge pixel with the colour of the nearest solid pixel;
alpha is untouched, so the silhouette stays the same. `save_webp()` writes with exact=True so the
encoder keeps those colours.

    python tool/sprite_edges.py            fix every sprite in assets/heroes (safe to re-run)
    python tool/sprite_edges.py --check    only report
"""
import glob
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

SOLID = 200  # alpha at or above this keeps its own colour
SKIP = ('identity.webp', 'back.webp', 'avatar.webp')  # opaque art


def bleed(im):
    im = im.convert('RGBA')
    a = np.array(im)
    solid = a[..., 3] >= SOLID
    if not solid.any() or solid.all():
        return im
    _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
    a[..., :3] = a[iy, ix, :3]
    a[..., :3] = np.where(solid[..., None], np.array(im)[..., :3], a[..., :3])
    return Image.fromarray(a, 'RGBA')


def save_webp(im, dest, quality=90, **_ignored):
    bleed(im).save(dest, 'WEBP', quality=quality, method=6, exact=True, alpha_quality=100)


def ring_dark_share(path):
    """Share of the transparent pixels hugging the figure that are black (0 = clean)."""
    a = np.array(Image.open(path).convert('RGBA')).astype(int)
    al = a[..., 3]
    solid = al > SOLID
    near = np.zeros_like(solid)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            near |= np.roll(np.roll(solid, dy, 0), dx, 1)
    ring = (al <= 20) & near
    return 0.0 if not ring.any() else float(((a[..., :3].sum(2) < 24) & ring).sum() / ring.sum())


def sprites(root):
    for p in sorted(glob.glob(os.path.join(root, 'assets', 'heroes', '*', '*.webp'))):
        if os.path.basename(p) in SKIP:
            continue
        if Image.open(p).mode == 'RGBA':
            yield p


if __name__ == '__main__':
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
    check = '--check' in sys.argv
    bad = fixed = 0
    for p in sprites(root):
        share = ring_dark_share(p)
        if share <= 0.2:
            continue
        bad += 1
        if not check:
            save_webp(Image.open(p), p)
            fixed += 1
    print(f'{bad} sprites with a black edge' + ('' if check else f', {fixed} rewritten'))

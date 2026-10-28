"""Draws the game's own maps in the printed Unmatched style and writes tool/maps_custom/<id>.png/.json.

Like the printed boards: an illustrated ground, thick black paths, space circles filled with
their zone colours (split into halves or thirds when a space is in several zones), numbered start
diamonds on the rim, and the UNMATCHED name plate in the corner. 1 unit = 1 space width.

Layouts: the 13 original maps (tool/maps_custom/old_layouts.json, respaced to printed spacing)
and two new 3v3 maps generated here (point-symmetric, so both teams get the same board).

    python tool/draw_maps.py [id ...]
"""
import json
import math
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

HERE = Path(__file__).resolve().parent
OUT = HERE / 'maps_custom'
FONTS = HERE.parent / 'assets' / 'fonts'
UNIT = 110  # pixels per unit (space width) in the drawn art
R = 0.495  # space radius, units
SPACING = 1.62  # printed boards: neighbouring spaces ~1.6 units apart

THEMES = {
    # ground colours (light, dark), accent, decorations
    'garden': ((0xC8, 0xC9, 0x8A), (0x7C, 0x8E, 0x55), 'trees', (0x5E, 0x9B, 0x4E)),
    'forest': ((0x9A, 0xA8, 0x6A), (0x4B, 0x63, 0x3A), 'trees', (0x3F, 0x7A, 0x3A)),
    'winter': ((0xE6, 0xEC, 0xF0), (0xA9, 0xB8, 0xC6), 'rocks', (0xFF, 0xFF, 0xFF)),
    'harbor': ((0xC9, 0xB8, 0x95), (0x8E, 0x7A, 0x5C), 'crates', (0x6A, 0x50, 0x34)),
    'marsh': ((0xA9, 0xAE, 0x7C), (0x5F, 0x6B, 0x46), 'reeds', (0x4E, 0x6B, 0x3D)),
    'desert': ((0xE6, 0xC2, 0x8A), (0xB5, 0x7E, 0x4F), 'rocks', (0xC9, 0x8A, 0x55)),
    'ruins': ((0xCF, 0xC4, 0xAE), (0x8F, 0x86, 0x76), 'stones', (0x9C, 0x93, 0x84)),
    'isle': ((0xE8, 0xD3, 0x9B), (0xA9, 0x9A, 0x66), 'trees', (0x4C, 0x8C, 0x48)),
    'keeps': ((0xBE, 0xBC, 0xA8), (0x7E, 0x7C, 0x6C), 'stones', (0x8A, 0x87, 0x7A)),
}


# ------------------------------------------------------------------------------------- layouts

def respace(m):
    """Old layouts are ~1.0 apart: spread them to printed spacing."""
    pts = {s['id']: (s['x'], s['y']) for s in m['spaces']}
    lens = sorted(math.dist(pts[a], pts[b]) for a, b in m['links'])
    med = lens[len(lens) // 2]
    mind = min(math.dist(pts[a], pts[b]) for a in pts for b in pts if a < b)
    k = max(SPACING / med, 1.32 / mind)
    cx = sum(p[0] for p in pts.values()) / len(pts)
    cy = sum(p[1] for p in pts.values()) / len(pts)
    for s in m['spaces']:
        s['x'], s['y'] = (s['x'] - cx) * k, (s['y'] - cy) * k
    return m


def segs_cross(p1, p2, p3, p4):
    def ccw(a, b, c):
        return (c[1] - a[1]) * (b[0] - a[0]) - (b[1] - a[1]) * (c[0] - a[0])
    if len({p1, p2, p3, p4}) < 4:
        return False
    return (ccw(p1, p3, p4) > 0) != (ccw(p2, p3, p4) > 0) and (ccw(p1, p2, p3) > 0) != (ccw(p1, p2, p4) > 0)


def generate(seed, name, theme, w=13.0, h=7.6, palette=None, river=False):
    """A new point-symmetric 3v3 board: spaces, paths, zones, 6 starts (team A left, team B right)."""
    rnd = random.Random(seed)
    mid = [(0.0, y) for y in (-3.0, -1.0, 1.0, 3.0)]
    half = []
    tries = 0
    while tries < 6000:
        tries += 1
        p = (rnd.uniform(-w / 2, -0.55), rnd.uniform(-h / 2, h / 2))
        if (all(math.dist(p, q) >= 1.0 for q in half) and all(math.dist(p, (-q[0], -q[1])) >= 1.0 for q in half)
                and all(math.dist(p, q) >= 1.0 for q in mid)):
            if math.dist(p, (-p[0], -p[1])) >= 1.0:
                half.append(p)
    pts = half + [(-x, -y) for x, y in half] + mid
    n = len(pts)
    mirror = {}
    for i, p in enumerate(pts):
        q = (-p[0], -p[1])
        mirror[i] = min(range(n), key=lambda j: math.dist(pts[j], q))
    # Paths: short non-crossing pairs, added with their mirror image.
    cand = sorted((math.dist(pts[a], pts[b]), a, b) for a in range(n) for b in range(a + 1, n) if math.dist(pts[a], pts[b]) < 1.5)
    links = set()
    deg = [0] * n

    def ok(a, b):
        if deg[a] >= 5 or deg[b] >= 5:
            return False
        return not any(segs_cross(pts[a], pts[b], pts[c], pts[d]) for c, d in links)

    for _, a, b in cand:
        pair = {tuple(sorted((a, b))), tuple(sorted((mirror[a], mirror[b])))}
        if all(l not in links for l in pair) and all(ok(*l) for l in pair):
            for l in pair:
                links.add(l)
                deg[l[0]] += 1
                deg[l[1]] += 1
    # Thin it out a little for chokepoints, keeping every space at 2+ paths and the board joined.
    def connected(ls):
        adj = {i: set() for i in range(n)}
        for a, b in ls:
            adj[a].add(b)
            adj[b].add(a)
        seen, todo = {0}, [0]
        while todo:
            for j in adj[todo.pop()]:
                if j not in seen:
                    seen.add(j)
                    todo.append(j)
        return len(seen) == n
    order = sorted(links, key=lambda l: rnd.random())
    for l in order:
        if rnd.random() > 0.22 or l not in links:
            continue
        pair = {l, tuple(sorted((mirror[l[0]], mirror[l[1]])))}
        trial = links - pair
        d2 = [0] * n
        for a, b in trial:
            d2[a] += 1
            d2[b] += 1
        if min(d2) >= 2 and connected(trial):
            links = trial
    # Zones: 5 seeds on the left and their mirrors, each its own colour.
    seeds = []
    while len(seeds) < 5:
        p = (rnd.uniform(-w / 2 + 0.8, -1.2), rnd.uniform(-h / 2 + 0.8, h / 2 - 0.8))
        if all(math.dist(p, q) > 2.2 for q in seeds):
            seeds.append(p)
    seeds += [(-x, -y) for x, y in seeds]
    keys = list(palette)
    zones = []
    for p in pts:
        d = sorted((math.dist(p, s), i) for i, s in enumerate(seeds))
        z = [keys[d[0][1]]]
        if d[1][0] - d[0][0] < 0.22:
            z.append(keys[d[1][1]])
        zones.append(z)
    # Starts: team A on the left (1 middle, 3 top, 5 bottom); team B their mirrors (2, 4, 6).
    left = [i for i in range(n) if pts[i][0] < -w / 2 + 2.6]
    s1 = min(left, key=lambda i: abs(pts[i][1]) + pts[i][0] * 0.2)
    s3 = min(left, key=lambda i: pts[i][1] + pts[i][0] * 0.3)
    s5 = max(left, key=lambda i: pts[i][1] - pts[i][0] * 0.3)
    starts = {s1: 1, mirror[s1]: 2, s3: 3, mirror[s3]: 4, s5: 5, mirror[s5]: 6}
    spaces = [{'id': i, 'x': pts[i][0], 'y': pts[i][1], 'zones': zones[i], 'start': starts.get(i)} for i in range(n)]
    return {
        'id': name[0], 'name': name[1], 'modes': ['3v3'], 'theme': theme, 'blurb': name[2], 'river': river,
        'zones': {k: v for k, v in palette.items() if any(k in z for z in zones)},
        'spaces': spaces, 'links': sorted(list(l) for l in links),
    }


# ------------------------------------------------------------------------------------- drawing

def noise(h, w, scale, rng):
    a = rng.random((max(2, h // scale + 2), max(2, w // scale + 2)))
    img = Image.fromarray((a * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(img).astype(np.float32) / 255


def hexrgb(c):
    c = c.lstrip('#')
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def draw_map(m, rng_seed):
    rng = np.random.default_rng(rng_seed)
    rnd = random.Random(rng_seed)
    pts = {s['id']: (s['x'], s['y']) for s in m['spaces']}
    xs = [p[0] for p in pts.values()]
    ys = [p[1] for p in pts.values()]
    margin = 1.15
    minx, maxx, miny, maxy = min(xs) - margin, max(xs) + margin, min(ys) - margin, max(ys) + margin
    W, H = int((maxx - minx) * UNIT), int((maxy - miny) * UNIT)
    cxu, cyu = (minx + maxx) / 2, (miny + maxy) / 2
    # Map coordinates: units from the image centre (the printed maps' convention).
    for s in m['spaces']:
        s['x'], s['y'] = round(s['x'] - cxu, 4), round(s['y'] - cyu, 4)
    P = {s['id']: ((s['x']) * UNIT + W / 2, (s['y']) * UNIT + H / 2) for s in m['spaces']}

    light, dark, deco, accent = THEMES.get(m['theme'], THEMES['ruins'])
    # Ground: two-colour painterly noise.
    n1 = noise(H, W, 180, rng) * 0.6 + noise(H, W, 60, rng) * 0.3 + noise(H, W, 14, rng) * 0.1
    n1 = ndimage.gaussian_filter(n1, 3)
    t = (n1 - n1.min()) / (n1.max() - n1.min() + 1e-6)
    ground = np.zeros((H, W, 3), np.float32)
    for i in range(3):
        ground[..., i] = light[i] * (1 - t * 0.75) + dark[i] * t * 0.75
    # Painted zone regions: each pixel takes the zone of its nearest space (like the printed
    # boards' rooms and fields), softly blended into the ground, with darker borders between them.
    yy, xx = np.mgrid[0:H, 0:W]
    ids = list(P)
    cs = np.array([P[i] for i in ids], np.float32)
    best = np.full((H, W), np.inf, np.float32)
    owner = np.zeros((H, W), np.int32)
    for k, (cx, cy) in enumerate(cs):
        dist = (xx - cx) ** 2 + (yy - cy) ** 2
        better = dist < best
        best[better] = dist[better]
        owner[better] = k
    zcol = np.array([hexrgb(m['zones'][s0['zones'][0]]['color']) for s0 in sorted(m['spaces'], key=lambda q: ids.index(q['id']))], np.float32)
    zkey = np.array([sorted(m['zones']).index(s0['zones'][0]) for s0 in sorted(m['spaces'], key=lambda q: ids.index(q['id']))])
    region = zcol[owner]
    for i in range(3):
        region[..., i] = ndimage.gaussian_filter(region[..., i], UNIT * 0.18)
    reach = np.clip(1.15 - np.sqrt(best) / (UNIT * 1.6), 0, 1)[..., None]
    ground = ground * (1 - 0.42 * reach) + (region * 0.85 + ground * 0.15) * 0.42 * reach
    # Water: a river across the middle, or the sea round the edge.
    water = np.zeros((H, W), bool)
    if m.get('river'):
        phase = rnd.uniform(0, 6)
        centre = W / 2 + np.sin(yy / H * 3.1 + phase) * W * 0.06
        water = np.abs(xx - centre) < UNIT * 0.32
    if m.get('sea'):
        e = np.minimum.reduce([xx, W - xx, yy, H - yy]).astype(np.float32)
        water = e < UNIT * (0.45 + 0.25 * noise(H, W, 90, rng))
    # Keep water away from spaces.
    near_space = np.zeros((H, W), bool)
    for cx, cy in P.values():
        near_space |= (xx - cx) ** 2 + (yy - cy) ** 2 < (UNIT * 0.62) ** 2
    water &= ~near_space
    wcol = np.array((0x5B, 0x9C, 0xC4), np.float32)
    ground[water] = ground[water] * 0.2 + wcol * 0.8
    img = Image.fromarray(np.clip(ground, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    # Water banks.
    if water.any():
        edge = water ^ ndimage.binary_erosion(water, iterations=3)
        arr = np.asarray(img).copy()
        arr[edge] = (40, 70, 92)
        img = Image.fromarray(arr)
        d = ImageDraw.Draw(img)

    # Free ground for decorations: away from spaces and paths.
    occ = Image.new('L', (W, H), 0)
    od = ImageDraw.Draw(occ)
    for a, b in m['links']:
        od.line([P[a], P[b]], fill=255, width=int(UNIT * 0.55))
    for cx, cy in P.values():
        od.ellipse([cx - UNIT * 0.8, cy - UNIT * 0.8, cx + UNIT * 0.8, cy + UNIT * 0.8], fill=255)
    free = (np.asarray(occ) == 0) & ~water
    # Worn trails under the paths.
    trail = Image.new('L', (W, H), 0)
    td = ImageDraw.Draw(trail)
    for a, b in m['links']:
        td.line([P[a], P[b]], fill=255, width=int(UNIT * 0.36))
    trail = trail.filter(ImageFilter.GaussianBlur(UNIT * 0.06))
    tcol = Image.new('RGB', (W, H), shade(light, 1.06))
    img = Image.composite(tcol, img, trail.point(lambda v: int(v * 0.55)))
    d = ImageDraw.Draw(img)
    free = ndimage.binary_erosion(free, iterations=int(UNIT * 0.25))
    draw_decor(d, free, deco, accent, rnd, W, H)

    # Paths: thick black, gently curved.
    pw = int(UNIT * 0.085)
    for a, b in m['links']:
        (ax, ay), (bx, by) = P[a], P[b]
        mx, my = (ax + bx) / 2, (ay + by) / 2
        L = math.dist((ax, ay), (bx, by))
        bend = rnd.uniform(-0.09, 0.09) * L
        nx, ny = -(by - ay) / L, (bx - ax) / L
        ctrl = (mx + nx * bend, my + ny * bend)
        curve = [((1 - t) ** 2 * ax + 2 * (1 - t) * t * ctrl[0] + t * t * bx, (1 - t) ** 2 * ay + 2 * (1 - t) * t * ctrl[1] + t * t * by)
                 for t in np.linspace(0, 1, 24)]
        d.line(curve, fill=(18, 16, 14), width=pw, joint='curve')

    # Spaces.
    r = R * UNIT
    for s in m['spaces']:
        cx, cy = P[s['id']]
        cols = [hexrgb(m['zones'][z]['color']) for z in s['zones']]
        draw_space(img, d, cx, cy, r, cols, rnd)
    d = ImageDraw.Draw(img)
    for s in m['spaces']:
        cx, cy = P[s['id']]
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(15, 13, 12), width=max(3, int(UNIT * 0.035)))
        if s['start']:
            draw_diamond(d, cx - r, cy, s['start'])

    draw_plate(d, m['name'], H)
    return img, {'W': W, 'H': H}


def draw_space(img, d, cx, cy, r, cols, rnd):
    box = [cx - r, cy - r, cx + r, cy + r]
    if len(cols) == 1:
        d.ellipse(box, fill=cols[0])
    elif len(cols) == 2:
        d.pieslice(box, 90, 270, fill=cols[0])
        d.pieslice(box, -90, 90, fill=cols[1])
    else:
        for i, c in enumerate(cols[:3]):
            d.pieslice(box, -90 + 120 * i, 30 + 120 * i, fill=c)
    # A printed texture: a fine pattern in a slightly darker shade, kept inside the circle.
    pat = Image.new('L', (int(2 * r) + 2, int(2 * r) + 2), 0)
    pd = ImageDraw.Draw(pat)
    style = sum(cols[0]) % 4
    step = max(6, int(r / 5))
    for k in range(-int(2 * r), int(4 * r), step):
        if style == 0:
            pd.line([(k, 0), (k - 2 * r, 2 * r)], fill=255, width=2)
        elif style == 1:
            for j in range(0, int(2 * r), step):
                pd.ellipse([k - 1.5, j - 1.5, k + 1.5, j + 1.5], fill=255)
        elif style == 2:
            pd.arc([k - step, 0 - step + (k // step % 2) * step, k + step, step + (k // step % 2) * step], 0, 180, fill=255, width=2)
            for j in range(0, int(2 * r), step * 2):
                pd.arc([k - step, j, k + step, j + 2 * step], 0, 180, fill=255, width=2)
        else:
            for j in range(0, int(2 * r), step):
                off = step // 2 if (j // step) % 2 else 0
                pd.line([(k + off, j), (k + off, j + step)], fill=255, width=2)
                pd.line([(k, j), (k + step, j)], fill=255, width=2)
    circ = Image.new('L', pat.size, 0)
    ImageDraw.Draw(circ).ellipse([1, 1, 2 * r, 2 * r], fill=70)
    from PIL import ImageChops
    mask = ImageChops.multiply(pat, circ)
    x0, y0 = int(cx - r), int(cy - r)
    region = img.crop((x0, y0, x0 + pat.width, y0 + pat.height))
    dark_ = region.point(lambda v: int(v * 0.8))
    region.paste(dark_, (0, 0), mask)
    img.paste(region, (x0, y0))
    d = ImageDraw.Draw(img)
    if len(cols) == 2:
        d.line([(cx, cy - r), (cx, cy + r)], fill=(110, 110, 110), width=3)
    elif len(cols) >= 3:
        for i in range(3):
            a = math.radians(-90 + 120 * i)
            d.line([(cx, cy), (cx + math.cos(a) * r, cy + math.sin(a) * r)], fill=(110, 110, 110), width=3)


def draw_diamond(d, x, y, n):
    s = UNIT * 0.15
    d.polygon([(x, y - s), (x + s, y), (x, y + s), (x - s, y)], fill=(16, 14, 12))
    f = ImageFont.truetype(str(FONTS / 'SairaCondensed-Bold.ttf'), int(UNIT * 0.19))
    d.text((x, y), str(n), font=f, fill=(235, 230, 220), anchor='mm')


def draw_plate(d, name, H):
    f1 = ImageFont.truetype(str(FONTS / 'SairaCondensed-ExtraBold.ttf'), int(UNIT * 0.2))
    f2 = ImageFont.truetype(str(FONTS / 'SairaCondensed-SemiBold.ttf'), int(UNIT * 0.17))
    x, y = int(UNIT * 0.3), H - int(UNIT * 0.62)
    hgt = int(UNIT * 0.34)
    w1 = int(d.textlength('UNMATCHED', font=f1)) + 18
    d.rectangle([x, y, x + w1, y + hgt], fill=(58, 52, 48), outline=(205, 200, 190), width=2)
    d.text((x + w1 / 2, y + hgt / 2), 'UNMATCHED', font=f1, fill=(235, 230, 220), anchor='mm')
    w2 = int(d.textlength(name.upper(), font=f2)) + 20
    d.rectangle([x + w1, y, x + w1 + w2, y + hgt], fill=(225, 220, 210), outline=(58, 52, 48), width=2)
    d.text((x + w1 + w2 / 2, y + hgt / 2), name.upper(), font=f2, fill=(50, 45, 40), anchor='mm')


def draw_decor(d, free, kind, accent, rnd, W, H):
    """A few groves / rock piles in the open ground, not a carpet of them."""
    ys, xs = np.nonzero(free[::12, ::12])
    spots = list(zip(xs * 12, ys * 12))
    rnd.shuffle(spots)
    groups = max(3, int(len(spots) / 260))
    centres = []
    for x, y in spots:
        if len(centres) >= groups:
            break
        if all(math.dist((x, y), c) > UNIT * 2.2 for c in centres):
            centres.append((x, y))
    for gx, gy in centres:
        members = [(gx + rnd.gauss(0, UNIT * 0.35), gy + rnd.gauss(0, UNIT * 0.3)) for _ in range(rnd.randint(4, 9))]
        members = [(x, y) for x, y in members if 0 <= int(y) < H and 0 <= int(x) < W and free[int(y), int(x)]]
        members.sort(key=lambda p: p[1])
        for x, y in members:
            s = UNIT * rnd.uniform(0.17, 0.27)
            if kind in ('trees', 'reeds'):
                base = accent
                d.ellipse([x - s, y - s * 0.55 + s * 0.9, x + s, y + s * 0.55 + s * 0.9], fill=(0, 0, 0, 60) if False else shade(base, 0.38))
                d.ellipse([x - s, y - s, x + s, y + s], fill=shade(base, rnd.uniform(0.85, 1.0)), outline=shade(base, 0.35), width=3)
                d.ellipse([x - s * 0.62, y - s * 0.72, x + s * 0.12, y - s * 0.02], fill=shade(base, 1.18))
            elif kind in ('rocks', 'stones'):
                k = rnd.randint(5, 7)
                poly = [(x + math.cos(a) * s * rnd.uniform(0.7, 1.0), y + math.sin(a) * s * rnd.uniform(0.55, 0.8))
                        for a in sorted(rnd.uniform(0, math.tau) for _ in range(k))]
                c = accent if kind == 'rocks' else (0x9A, 0x92, 0x86)
                d.polygon([(px, py + s * 0.25) for px, py in poly], fill=shade(c, 0.45))
                d.polygon(poly, fill=shade(c, rnd.uniform(0.9, 1.05)), outline=shade(c, 0.4), width=3)
                d.line([poly[0], poly[len(poly) // 2]], fill=shade(c, 0.7), width=2)
            elif kind == 'crates':
                c = accent
                d.rectangle([x - s * 0.6, y - s * 0.6 + s * 0.3, x + s * 0.6, y + s * 0.6 + s * 0.3], fill=shade(c, 0.4))
                d.rectangle([x - s * 0.6, y - s * 0.6, x + s * 0.6, y + s * 0.6], fill=shade(c, 1.15), outline=shade(c, 0.4), width=3)
                d.line([(x - s * 0.6, y), (x + s * 0.6, y)], fill=shade(c, 0.6), width=2)


# ------------------------------------------------------------------------------------- main

NEW_3V3 = [
    (('ironwood', 'Ironwood Crossing', 'Two warbands meet at the ford of an old forest. Point-symmetric: both sides walk the same roads.'),
     'forest', 11, True,
     {'moss': {'name': 'Moss Bank', 'color': '#8fbf6a'}, 'fern': {'name': 'Fern Hollow', 'color': '#5f9e57'},
      'amber': {'name': 'Amber Glade', 'color': '#e8b25c'}, 'clay': {'name': 'Clay Path', 'color': '#c98a5e'},
      'stone': {'name': 'Standing Stones', 'color': '#b9b6ad'}, 'bluebell': {'name': 'Bluebell Dell', 'color': '#8fb3e2'},
      'heath': {'name': 'Heather Heath', 'color': '#b597d6'}, 'rose': {'name': 'Wild Rose', 'color': '#e99aa9'},
      'pine': {'name': 'Pine Ridge', 'color': '#3f7f6a'}, 'sun': {'name': 'Sunlit Ford', 'color': '#f0d36b'}}),
    (('citadel', 'Sunken Citadel', 'A drowned fortress at low tide. Its halls and causeways mirror each other for both teams.'),
     'ruins', 29, False,
     {'gate': {'name': 'Sea Gate', 'color': '#7fb6d4'}, 'hall': {'name': 'Great Hall', 'color': '#d8a35b'},
      'chapel': {'name': 'Chapel', 'color': '#c07dbd'}, 'well': {'name': 'Old Well', 'color': '#86c08d'},
      'tower': {'name': 'Watchtower', 'color': '#d36e5e'}, 'yard': {'name': 'Courtyard', 'color': '#e5d6a4'},
      'crypt': {'name': 'Crypt', 'color': '#8e8aa6'}, 'garden': {'name': 'Sunken Garden', 'color': '#5fa08a'},
      'forge': {'name': 'Forge', 'color': '#e08c4a'}, 'keep': {'name': 'Inner Keep', 'color': '#a7a39a'}}),
]


def main():
    only = set(sys.argv[1:])
    OUT.mkdir(exist_ok=True)
    old = json.loads((OUT / 'old_layouts.json').read_text(encoding='utf-8'))
    layouts = [respace(dict(m, modes=[m['mode']])) for m in old.values()]
    for (meta, theme, seed, river, palette) in NEW_3V3:
        layouts.append(respace(generate(seed, meta, theme, palette=palette, river=river)))
    for i, m in enumerate(layouts):
        if only and m['id'] not in only:
            continue
        m.pop('mode', None)
        img, size = draw_map(m, 1000 + i)
        img.save(OUT / f"{m['id']}.png")
        m['art'] = {'file': f"{m['id']}.webp", 'w': size['W'], 'h': size['H'], 'unitPx': UNIT}
        m.setdefault('oneway', [])
        m.setdefault('stairs', [])
        m.setdefault('set', '')
        (OUT / f"{m['id']}.json").write_text(json.dumps(m, indent=1), encoding='utf-8')
        print(f"{m['id']:8} {m['name']:22} {','.join(m['modes']):4} spaces={len(m['spaces'])} links={len(m['links'])} "
              f"starts={sum(1 for s in m['spaces'] if s['start'])} art={size['W']}x{size['H']}")


if __name__ == '__main__':
    main()

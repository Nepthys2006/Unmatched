"""Draws the game's logo and every app icon from it, so web, Android and Windows all match.

The mark: UNMATCHED in tall, widely spaced capitals over a cut pennant that reads FAN MADE
(FAN heavy and slanted, MADE light), white on black. Fonts: Saira Condensed (OFL), the game's own
title face, in its Light and Black weights (tool/fonts/).

    python tool/make_icon.py        (needs Pillow)

Writes:
    assets/brand/logo.png, logo-wide.png          the mark (square, and 1200x630 for sharing)
    android/app/src/main/res/mipmap-*/ic_launcher.png
    windows/runner/resources/app_icon.ico
    web/favicon.png, web/icons/Icon-*.png
    ../landing/img/logo.png, ../landing/img/og.png
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / 'tool' / 'fonts'
WHITE, BLACK = (255, 255, 255, 255), (0, 0, 0, 255)


def font(weight: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / f'SairaCondensed-{weight}.ttf'), size)


def spaced(draw, text, f, box_w, y, fill, tracking):
    """Draws [text] centred in a box [box_w] wide, with [tracking] extra px between letters."""
    widths = [draw.textlength(c, font=f) for c in text]
    total = sum(widths) + tracking * (len(text) - 1)
    x = (box_w - total) / 2
    for c, w in zip(text, widths):
        draw.text((x, y), c, font=f, fill=fill)
        x += w + tracking
    return total


def text_layer(text, f, fill, stroke=0, stroke_fill=None):
    l, t, r, b = f.getbbox(text, stroke_width=stroke)
    im = Image.new('RGBA', (r - l + 8, b - t + 8), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((4 - l, 4 - t), text, font=f, fill=fill, stroke_width=stroke, stroke_fill=stroke_fill)
    return im


def shear(im, k):
    """Slants a layer to the right by k (x shift per unit of height, from the bottom)."""
    w, h = im.size
    extra = int(abs(k) * h) + 2
    return im.transform((w + extra, h), Image.AFFINE, (1, k, -k * h if k > 0 else 0, 0, 1, 0), resample=Image.BICUBIC)


def mark(size: int) -> Image.Image:
    """The square mark on transparent: UNMATCHED over the FAN MADE pennant, white."""
    S = size
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # Top line: light capitals stretched tall (1.45x), tracked wide across 86% of the width.
    f_top = font('Light', 200)
    letters = [text_layer(c, f_top, WHITE) for c in 'UNMATCHED']
    letters = [l.resize((l.width, int(l.height * 1.45)), Image.LANCZOS) for l in letters]
    track = 0.32 * letters[0].width
    raw_w = sum(l.width for l in letters) + track * 8
    k = S * 0.86 / raw_w
    x = (S - raw_w * k) / 2
    top_y = S * 0.06
    for l in letters:
        l2 = l.resize((max(1, int(l.width * k)), max(1, int(l.height * k))), Image.LANCZOS)
        im.alpha_composite(l2, (int(x), int(top_y)))
        x += (l.width + track) * k
    top_bottom = top_y + letters[0].height * k

    # Pennant: a white shape with the same shape cut out inside it (clean, mitred corners), a
    # box with a shallow point at the bottom.
    x0, x1 = S * 0.07, S * 0.93
    y0 = top_bottom + S * 0.07
    y1, tip = S * 0.80, S * 0.94
    t = S * 0.024
    outer = [(x0, y0), (x1, y0), (x1, y1), (S / 2, tip), (x0, y1)]
    inner = [(x0 + t, y0 + t), (x1 - t, y0 + t), (x1 - t, y1 - t * 0.35), (S / 2, tip - t * 1.15), (x0 + t, y1 - t * 0.35)]
    shape = Image.new('L', (S, S), 0)
    ImageDraw.Draw(shape).polygon(outer, fill=255)
    ImageDraw.Draw(shape).polygon(inner, fill=0)
    im.paste(Image.new('RGBA', (S, S), WHITE), (0, 0), shape)

    # FAN: black weight, slanted, solid, with a bold slanted bar under it. MADE: light, hollow.
    fan = shear(text_layer('FAN', font('Black', 400), WHITE), 0.2)
    made = text_layer('MADE', font('Light', 400), (0, 0, 0, 0), stroke=9, stroke_fill=WHITE)
    gap = 40
    total = fan.width + gap + made.width
    k = (x1 - x0 - 2 * t) * 0.9 / total
    fan = fan.resize((int(fan.width * k), int(fan.height * k)), Image.LANCZOS)
    made = made.resize((int(made.width * k), int(made.height * k)), Image.LANCZOS)
    left = (S - (fan.width + gap * k + made.width)) / 2
    mid = y0 + (tip - y0) * 0.43
    fy = int(mid - fan.height / 2)
    im.alpha_composite(fan, (int(left), fy))
    im.alpha_composite(made, (int(left + fan.width + gap * k), int(mid - made.height / 2)))
    bar_y = fy + fan.height + S * 0.012
    bh = S * 0.03
    d.polygon([(left + S * 0.01, bar_y), (left + fan.width * 0.93, bar_y + bh * 0.55),
               (left + fan.width * 0.93, bar_y + bh * 1.55), (left + S * 0.01, bar_y + bh)], fill=WHITE)
    return im


def rounded(size, radius, fill):
    im = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(im).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=fill)
    return im


def icon(size: int, pad: float = 0.12, round_: bool = True) -> Image.Image:
    """The app icon: the mark on a black tile (rounded, or square for maskable/adaptive use)."""
    big = 1024
    tile = rounded(big, int(big * 0.2) if round_ else 0, BLACK)
    m = mark(int(big * (1 - 2 * pad)))
    tile.alpha_composite(m, (int(big * pad), int(big * pad)))
    return tile.resize((size, size), Image.LANCZOS)


def main():
    brand = ROOT / 'assets' / 'brand'
    brand.mkdir(parents=True, exist_ok=True)
    icon(1024).save(brand / 'logo.png')

    # Sharing image / wide logo: the mark at left on black, like a banner card.
    wide = Image.new('RGBA', (1200, 630), BLACK)
    wide = Image.alpha_composite(Image.new('RGBA', wide.size, (0, 0, 0, 0)), rounded_wide(1200, 630, 48))
    m = mark(560)
    wide.alpha_composite(m, (320, 35))
    wide.save(brand / 'logo-wide.png')

    # Android launcher icons (legacy square icons; the black tile fills them).
    for folder, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        icon(px).save(ROOT / 'android' / 'app' / 'src' / 'main' / 'res' / f'mipmap-{folder}' / 'ic_launcher.png')

    # Windows .ico with every size Explorer asks for.
    ico = icon(256)
    ico.save(ROOT / 'windows' / 'runner' / 'resources' / 'app_icon.ico', sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

    # Web: favicon, home-screen icons, maskable ones with a safe margin and square corners.
    web = ROOT / 'web'
    icon(64).save(web / 'favicon.png')
    icon(192).save(web / 'icons' / 'Icon-192.png')
    icon(512).save(web / 'icons' / 'Icon-512.png')
    icon(192, pad=0.2, round_=False).save(web / 'icons' / 'Icon-maskable-192.png')
    icon(512, pad=0.2, round_=False).save(web / 'icons' / 'Icon-maskable-512.png')

    # Landing page.
    landing = ROOT.parent / 'landing' / 'img'
    if landing.exists():
        icon(256).save(landing / 'logo.png')
        wide.convert('RGB').save(landing / 'og.png')
    print('icons written')


def rounded_wide(w, h, r):
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(im).rounded_rectangle((0, 0, w - 1, h - 1), radius=r, fill=BLACK)
    return im


if __name__ == '__main__':
    main()

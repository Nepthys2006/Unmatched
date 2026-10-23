"""
Builds the game's data and image assets from the Unmatched folder.

    python tool/build_assets.py [--images]

Data (always):
    assets/data/heroes.json   all 70 heroes of ../heroes.json (the app offers the scripted ones):
                              stats, fighters, ability text and every card. Card text comes from
                              ../heroes.json, corrected by tool/card_fixes.json after checking it
                              against the printed cards.
Images (--images, skips files that exist):
    assets/cards/<hero>/NN.webp            600x832 card faces
    assets/heroes/<hero>/avatar.webp       256x256
    assets/heroes/<hero>/mini.webp         standee art, 440 px tall, transparent
    assets/heroes/<hero>/back.webp         card back, 600 px wide
    assets/heroes/<hero>/identity.webp     hero card, 600 px wide
    assets/heroes/<hero>/<fighter>.webp    sidekick token, 160x160
"""

import json
import os
import re
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
ROOT = os.path.dirname(GAME)                       # the Unmatched folder
CARDS_SRC = os.path.join(ROOT, "3D Map", "assets", "cards")

slug = lambda s: re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")
norm = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())
TIMING = {"effect": "effect", "immediately": "immediately", "during combat": "during",
          "after combat": "after", "ongoing": "ongoing", "boost": "boosted"}


def fighters_of(h):
    out = [{"id": h["id"], "name": h["name"], "hero": True, "attack": h["attack"].lower().replace("range", "ranged").replace("rangedd", "ranged"),
            "hp": int(h["health"]), "count": 1}]
    for s in h["sidekicks"]:
        out.append({"id": slug(s["name"]), "name": s["name"], "hero": False,
                    "attack": s["attack"].lower().replace("range", "ranged").replace("rangedd", "ranged"),
                    "hp": int(s["health"]), "count": int(s["count"])})
    return out


# Labels in ../heroes.json that are typos or forms of a fighter.
ALIASES = {"allice": "alice", "thepotter": "theporter", "djkstra": "dijkstra", "harpy": "harpies",
           "drjekyll": "jekyllhyde", "mrhyde": "jekyllhyde",
           "ali": "muhammadali", "jilltrent": "drjilltrent"}


def match_fighter(label, fighters):
    """Map a card's 'used by' label to fighter ids ([] = any fighter)."""
    n = norm(label)
    n = ALIASES.get(n, n)
    if n in ("", "any"):
        return []
    for f in fighters:
        names = {norm(f["name"]), norm(f["name"]).removeprefix("the"), norm(f["name"]).rstrip("s"),
                 norm(f["name"]).removeprefix("the").rstrip("s")}
        names |= {norm(w) for w in f["name"].split() if len(w) > 3}
        if n in names or n.removeprefix("the") in names or n.rstrip("s") in names:
            return [f["id"]]
    return None


def build_data():
    heroes = {h["name"]: h for h in json.load(open(os.path.join(ROOT, "heroes.json"), encoding="utf-8"))}
    # The 3D table's 39 heroes first (their order is the original roster), then every other hero
    # in ../heroes.json. The app only offers heroes whose scripts are done (engine registry).
    roster = list(json.load(open(os.path.join(ROOT, "3D Map", "src", "herodata.json"), encoding="utf-8")))
    roster += [n for n in heroes if n not in roster]
    fixes = json.load(open(os.path.join(HERE, "card_fixes.json"), encoding="utf-8"))
    out, unresolved = [], []
    for name in roster:
        h = heroes[name]
        fighters = fighters_of(h)
        hf = fixes.get(h["id"], {})
        for f in fighters:
            f.update(hf.get("fighters", {}).get(f["id"], {}))
        cards = []
        for i, c in enumerate(h["deck"], 1):
            text = {}
            for k, v in c["effects"].items():
                text[TIMING.get(k.lower(), k.lower())] = re.sub(r"\s+", " ", v).strip()
            card = {
                "index": i, "title": c["title"].strip(), "type": c["type"],
                "value": None if c["value"] in ("-", "", "?") else int(c["value"]),
                "boost": None if c["boost"] in ("-", "", "?") else int(c["boost"]),
                "copies": int(c["copies"]), "usedBy": c["used_by"].strip(), "text": text,
            }
            card["fighters"] = match_fighter(card["usedBy"], fighters)
            card.update(hf.get("cards", {}).get(str(i), {}))
            if card["fighters"] is None:
                unresolved.append(f"{h['id']}/{i} {card['title']}: used by '{card['usedBy']}'")
                card["fighters"] = []
            cards.append(card)
        hero = {
            "id": h["id"], "name": h["name"], "set": h["set"], "color": h["color"],
            "move": int(h["move"]), "ability": h["ability"].strip(), "description": h["description"].strip(),
            "fighters": fighters, "cards": cards,
        }
        hero.update(hf.get("hero", {}))
        out.append(hero)
    os.makedirs(os.path.join(GAME, "assets", "data"), exist_ok=True)
    json.dump(out, open(os.path.join(GAME, "assets", "data", "heroes.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    n = sum(len(h["cards"]) for h in out)
    print(f"heroes.json: {len(out)} heroes, {n} cards")
    for u in unresolved:
        print("  unresolved fighter:", u)
    return heroes, out


def save(im, path, **kw):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, "WEBP", method=6, **kw)


def build_images(src_heroes, out):
    done = 0
    for h in out:
        hid = h["id"]
        src = src_heroes[h["name"]]
        dst = os.path.join(GAME, "assets", "heroes", hid)
        cdst = os.path.join(GAME, "assets", "cards", hid)
        for c in h["cards"]:
            p = os.path.join(cdst, f"{c['index']:02d}.webp")
            if not os.path.exists(p):
                im = Image.open(os.path.join(CARDS_SRC, hid, f"{c['index']:02d}.webp")).convert("RGBA")
                save(im.resize((600, 832), Image.LANCZOS), p, quality=80, exact=True)
                done += 1
        jobs = {
            "back.webp": (os.path.join(CARDS_SRC, hid, "back.webp"), lambda im: im.resize((600, 832), Image.LANCZOS)),
            "identity.webp": (os.path.join(CARDS_SRC, hid, "identity.webp"), lambda im: im.resize((600, 832), Image.LANCZOS)),
            "avatar.webp": (os.path.join(ROOT, src["art"]["Avatar"]), lambda im: im.resize((256, 256), Image.LANCZOS)),
            "mini.webp": (os.path.join(ROOT, src["art"]["Miniature"]), lambda im: trim_resize(im, 440)),
        }
        for f in h["fighters"][1:]:
            key = next((k for k in src["art"] if k.startswith("Sidekick") and norm(k.split(" - ", 1)[1]) == norm(f["name"])), None)
            if key:
                jobs[f"{f['id']}.webp"] = (os.path.join(ROOT, src["art"][key]), lambda im: im.resize((160, 160), Image.LANCZOS))
        for name, (p, fn) in jobs.items():
            o = os.path.join(dst, name)
            if not os.path.exists(o):
                save(fn(Image.open(p).convert("RGBA")), o, quality=82, exact=True)
                done += 1
    print(f"images written: {done}")


def trim_resize(im, height):
    box = im.getchannel("A").getbbox()
    if box:
        im = im.crop(box)
    w = round(im.width * height / im.height)
    return im.resize((w, height), Image.LANCZOS)


if __name__ == "__main__":
    src, out = build_data()
    if "--images" in sys.argv:
        build_images(src, out)

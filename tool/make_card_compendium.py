"""Builds CARDS.md (every hero's identity card and deck, with values and effects) and
CARD_TODO.md (a per-hero implementation checklist) from assets/data/heroes.json.

Run from the project root:  python tool/make_card_compendium.py
Re-run after changing heroes.json, a hero script or registry.dart so both files stay in sync.
"""
import glob
import json
import re
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HEROES = ROOT / 'assets' / 'data' / 'heroes.json'
SCRIPTS = ROOT / 'lib' / 'engine' / 'heroes'
REGISTRY = SCRIPTS / 'registry.dart'
BUGS = ROOT / 'bugs.md'

TYPE_LABEL = {'attack': 'Attack', 'defense': 'Defense', 'versatile': 'Versatile', 'scheme': 'Scheme'}
# Card text sections, in the order they resolve.
SECTIONS = [
    ('effect', 'Effect'),
    ('immediately', 'IMMEDIATELY'),
    ('during', 'DURING COMBAT'),
    ('after', 'AFTER COMBAT'),
    ('ongoing', 'ONGOING'),
    ('boosted', 'BOOSTED WITH'),
    ('completion', 'COMPLETION (line of exactly 10 syllables)'),
]
INGREDIENT = {'snake': 'snake', 'bat': 'bat', 'lizard': "lizard's leg"}

# Things the identity card does not say but that matter for this hero (official set rules),
# plus anything taken from an unofficial source.
SET_RULES = {
    'squirrel-girl': 'Squirrels are small fighters: up to 4 share a space with one other fighter; they are adjacent to '
                     'fighters in their space; opposing fighters move through them and they move through opposing '
                     'fighters; damage to one squirrel is taken by every squirrel in its space. Summoning: an empty '
                     'space next to Squirrel Girl; if all 8 are out, move one of them there instead.',
    'shakespeare': 'Iambic Pentameter: each card he or an Actor attacks or defends with goes face up into his line '
                   '(not the discard pile). Each card shows its syllables. Exactly 10 syllables: resolve the last '
                   "card's COMPLETION effect (even if its other effects were canceled), then discard the line. More "
                   'than 10: discard the line with no completion. Boosts and discards go to the discard pile.',
    'the-wayward-sisters': 'Three Sisters, each with her own health; you lose when the last one falls; any Sister plays '
                           'any card. Every card has an ingredient (snake, bat, lizard\'s leg). Cards that would go to '
                           'the discard pile (played, boosted, discarded) go into the cauldron. After you attack you '
                           'may cast one spell you have the ingredients for, then discard the whole cauldron. '
                           '**Spells (UNVERIFIED, from a fan guide, not the printed card):** snake + bat: draw 1 card, '
                           'one of your fighters recovers 1 health; snake + lizard: move any fighter up to 3 spaces; '
                           'lizard + bat: deal 1 damage to a fighter in a zone with any of your fighters; all three: '
                           'gain 1 action.',
    'oda-nobunaga': 'Flanked: an opposing fighter adjacent to two or more fighters you control (teammates\' fighters '
                    'do not count).',
    'tomoe-gozen': 'Attack of Opportunity happens however the hero leaves her zone (moved, pushed, placed, swapped), '
                   'several times in one move if they leave again; not when Tomoe is the one moving; heroes only.',
    'krang': "**UNVERIFIED:** the Die of Ultimate Destruction faces are assumed to be blank, 1, 1, 2, 2, 3.",
}


# Rules questions no official source settled; how the engine plays them now.
DECISIONS = [
    "Squirrel Girl: summoned squirrels go into empty spaces (the set's summoning rule), also for Get 'Em "
    "Tippy-Toe! (\"any space\") and Eat Nuts; only Squirmish puts one in Squirrel Girl's own space.",
    'Squirrel Girl: Go Nuts is optional ("you may summon", set rules), so the player can skip it.',
    'Tomoe Gozen: Attack of Opportunity is not triggered when a hero vanishes or returns by its own '
    "ability (Invisible Man, Leshen, Bullseye); it is for moves, places, pushes and swaps.",
    'The Wayward Sisters: no spell is cast after an attack whose card ended the turn.',
    'Dr. Jill Trent: no gadget is active before her first turn (Hypnotist does nothing until then).',
]


def github_anchor(text):
    # GitHub's heading anchors: lowercase, drop punctuation, each space becomes a hyphen.
    return re.sub(r'[^a-z0-9 _-]', '', text.lower()).replace(' ', '-')


def cell(text):
    return str(text).replace('|', '\\|').replace('\n', ' ')


def attack_value(c):
    return c['value'] if c['type'] in ('attack', 'versatile') and c['value'] is not None else '—'


def defense_value(c):
    return c['value'] if c['type'] in ('defense', 'versatile') and c['value'] is not None else '—'


def boost_value(c):
    if c.get('dieBoost'):
        return '? (die)'
    return c['boost'] if c.get('boost') else '—'


def section_text(c, key):
    text = (c.get('text') or {}).get(key)
    if not text:
        return None
    if key == 'boosted':
        text = re.sub(r'^BOOSTED WITH:\s*', '', text)
    return text


def ability_parts(h):
    """(name, text) of the special ability; the first line is its name when it is short."""
    lines = [l.strip() for l in h['ability'].strip().split('\n') if l.strip()]
    if len(lines) > 1 and len(lines[0]) <= 40 and not lines[0].endswith('.'):
        return lines[0], ' '.join(lines[1:])
    return None, ' '.join(lines)


def engine_notes():
    """Hero id -> the doc comment on its script class (how the engine plays the ability)."""
    classes = dict(re.findall(r"'([a-z0-9-]+)': (\w+)\.new", REGISTRY.read_text(encoding='utf-8')))
    docs = {}
    for f in glob.glob(str(SCRIPTS / '*.dart')):
        for m in re.finditer(r'((?:^///.*\n)+)class (\w+) extends HeroScript', Path(f).read_text(encoding='utf-8'), re.M):
            docs[m.group(2)] = ' '.join(l.strip()[3:].strip() for l in m.group(1).splitlines())
    return {hid: docs.get(cls, '') for hid, cls in classes.items()}


def fighter_line(f):
    role = 'Hero' if f['hero'] else 'Sidekick'
    return f'| {cell(f["name"])} | {role} | {f["attack"].capitalize()} | {f["hp"]} | {f["count"]} |'


def main():
    heroes = json.loads(HEROES.read_text(encoding='utf-8'))
    notes = engine_notes()
    scripted = set(notes)

    sets = OrderedDict()
    for h in heroes:
        sets.setdefault(h['set'], []).append(h)

    total_cards = sum(c['copies'] for h in heroes for c in h['cards'])
    done = [h for h in heroes if h['id'] in scripted]
    todo = [h for h in heroes if h['id'] not in scripted]

    # ---------- CARDS.md ----------
    out = ['# Unmatched: hero and card compendium', '']
    out.append("Every hero's **identity card** (health, move, attack type, sidekicks, special ability) and "
               '**deck** (attack, defense and boost values, and the immediately / during / after combat effects), '
               'taken from `assets/data/heroes.json` (corrected against the printed cards, see `tool/card_fixes.json`).')
    out.append('')
    out.append(f'**{len(heroes)} heroes, {sum(len(h["cards"]) for h in heroes)} different cards, '
               f'{total_cards} cards counting copies.** Scripted in the engine: {len(done)} of {len(heroes)}.')
    out.append('')
    out.append('Generated by `python tool/make_card_compendium.py`; do not edit by hand.')
    out.append('')
    out.append('## How to read it')
    out.append('')
    out.append('- **Identity card**: the hero and sidekicks with their attack type (melee: adjacent only; ranged: '
               'adjacent or anywhere in a shared zone), starting health and how many there are; the move value is '
               'shared by all of the hero\'s fighters.')
    out.append('- **In this game**: how the engine plays the special ability (from the hero script).')
    out.append('- **ATK**: value when played as an attack (attack and versatile cards); the damage before the '
               'defense is subtracted.')
    out.append('- **DEF**: value when played as a defense (defense and versatile cards).')
    out.append('- **BOOST**: value added when the card is discarded to boost movement or a combat card. '
               '"—" means it cannot boost; "? (die)" is a die roll.')
    out.append('- **Effect order in combat**: IMMEDIATELY → DURING COMBAT → damage → AFTER COMBAT. '
               "The defender's effect resolves first at each step.")
    out.append('- Schemes have no ATK/DEF; their text is under *Effect*.')
    out.append('')
    out.append('## Heroes')
    out.append('')
    for set_name, hs in sets.items():
        links = ', '.join(f'[{h["name"]}](#{github_anchor(h["name"])})' for h in hs)
        out.append(f'- **{set_name}**: {links}')
    out.append('')

    for set_name, hs in sets.items():
        out.append(f'---\n\n# Set: {set_name}')
        out.append('')
        for h in hs:
            status = 'scripted and tested' if h['id'] in scripted else '**not scripted yet**'
            out.append(f'## {h["name"]}')
            out.append('')
            out.append(f'*{cell(h["description"])}*' if h.get('description') else '')
            out.append('')
            out.append('### Identity card')
            out.append('')
            out.append(f'**Move {h["move"]}** · Deck: {sum(c["copies"] for c in h["cards"])} cards · Engine: {status}')
            out.append('')
            out.append('| Fighter | Role | Attack | Health | Count |')
            out.append('|---|---|---|---|---|')
            out.extend(fighter_line(f) for f in h['fighters'])
            out.append('')
            name, text = ability_parts(h)
            out.append(f'**Special ability{": " + name if name else ""}.** {cell(text)}')
            out.append('')
            if h['id'] in SET_RULES:
                out.append(f'**Set rules.** {SET_RULES[h["id"]]}')
                out.append('')
            if notes.get(h['id']):
                out.append(f'**In this game.** {cell(notes[h["id"]])}')
                out.append('')
            out.append('### Deck')
            out.append('')
            extra = any(c.get('syllables') or c.get('ingredient') for c in h['cards'])
            head = '| # | Card | Type | Copies | Used by | ATK | DEF | BOOST |' + (' Extra |' if extra else '')
            out.append(head)
            out.append('|' + '---|' * (head.count('|') - 1))
            for c in h['cards']:
                row = (f'| {c["index"]} | {cell(c["title"])} | {TYPE_LABEL[c["type"]]} | {c["copies"]} | '
                       f'{cell(c["usedBy"])} | {attack_value(c)} | {defense_value(c)} | {boost_value(c)} |')
                if extra:
                    bits = []
                    if c.get('syllables'):
                        bits.append(f'{c["syllables"]} syllables')
                    if c.get('ingredient'):
                        bits.append(INGREDIENT.get(c['ingredient'], c['ingredient']))
                    row += f' {", ".join(bits)} |'
                out.append(row)
            out.append('')
            for c in h['cards']:
                parts = [(label, section_text(c, key)) for key, label in SECTIONS]
                parts = [(label, t) for label, t in parts if t]
                if not parts:
                    out.append(f'- **{c["title"]}**: no effect.')
                    continue
                out.append(f'- **{c["title"]}**')
                for label, t in parts:
                    out.append(f'  - *{label}:* {t}')
            out.append('')

    (ROOT / 'CARDS.md').write_text('\n'.join(out) + '\n', encoding='utf-8')

    # ---------- CARD_TODO.md ----------
    t = ['# Hero and card implementation checklist', '']
    t.append("One box per identity card detail, special ability and card (its ATK / DEF / BOOST values and every "
             'effect). Details are in `CARDS.md`. A hero box is ticked when it is scripted in `lib/engine/heroes/` '
             'and tested: every card by `test/cards_all_test.dart`, every identity card by '
             '`test/identity_all_test.dart`, every ability by a hero test (`test/heroes_*_test.dart`).')
    t.append('')
    t.append('Generated by `python tool/make_card_compendium.py` (re-run it after scripting a hero).')
    t.append('')
    t.append(f'**Engine progress: {len(done)} / {len(heroes)} heroes scripted.**')
    t.append('')
    t.append('## Identity cards in the UI (every hero)')
    t.append('')
    t.append("- [x] Hero select shows the identity card (tap to read it), health, move, attack type, sidekicks and special ability.")
    t.append("- [x] In a match, the Identity cards button (top left) or any player's plate opens every player's identity card, ability, live state and set rules (`test/match_hud_test.dart`).")
    t.append('- [x] Fighters start at the identity card health, attack type, move, hand and deck size (`test/identity_all_test.dart`, all 70 heroes).')
    t.append('- [x] Ranged fighters can target anyone in a shared zone; melee only adjacent (engine tests; targets are highlighted from the same legal actions).')
    t.append('- [x] Ability status chips show the live state (BIG/SMALL, gadget, line syllables, cauldron, squirrels...) on your plate and in the identity sheet.')
    t.append('- [x] Heroes with several hero fighters (Raptors, Cloak & Dagger, The Wayward Sisters) show one dial per fighter.')
    t.append('- [x] Set rules are explained in the identity sheet under RULES TO KNOW (small fighters, the line, the cauldron and spells, flanked).')
    t.append('')
    t.append('## Card rules in the UI (every card)')
    t.append('')
    t.append("- [x] Every card's printed ATK / DEF starts its value breakdown and every BOOST value is right (`test/cards_all_test.dart`, 880 cards).")
    t.append('- [x] Every card is really played (615 attacks, 462 defenses, 151 schemes; none skipped) and ends up in the right pile afterwards: discard, line, cauldron, hand, deck or removed.')
    t.append("- [ ] Combat panel shows each card's ATK or DEF, every boost added, and modifiers (`game.valueOf`).")
    t.append('- [x] Cards with no BOOST ("—") are never offered for boosting (only cards that can boost are offered; checked for all 880 cards).')
    t.append('- [ ] IMMEDIATELY effects resolve before DURING COMBAT, defender first; the step is highlighted.')
    t.append('- [ ] DURING COMBAT value changes ("the value is X instead", "+1 per...") show in the breakdown.')
    t.append('- [ ] AFTER COMBAT effects run after damage, including when the fighter was defeated where the card says so.')
    t.append('- [ ] "Draw N cards" effects add the cards to the hand and the hand count updates.')
    t.append("- [ ] \"Look at / choose a card for them to discard\" shows the opponent's hand to the chooser only.")
    t.append('- [ ] Effects on "each opponent" / "all enemies" hit every enemy in team and free-for-all modes.')
    t.append('- [ ] Canceled effects (all, or only DURING/AFTER) are greyed out in the combat panel.')
    t.append('- [ ] BOOSTED WITH effects trigger only when that card was used as a boost.')
    t.append('- [ ] ONGOING schemes stay on the table with their discard condition shown.')
    t.append("- [x] Shakespeare's line is visible (identity sheet: cards in order, syllables) and completions are announced in the log.")
    t.append("- [x] The Wayward Sisters' cauldron is visible (identity sheet: cards and ingredients) and spells are offered after attacking.")
    t.append('- [x] Squirrels sharing a space are drawn side by side and each can be tapped (2D and 3D).')
    t.append('')
    t.append('## Match screen')
    t.append('')
    t.append('- [x] Hand cards are shown whole, above the bottom edge, clear of the name plate and the action buttons (phone and desktop).')
    t.append('- [x] Camera controls (zoom, fit, turn, tilt) fold into one dropdown button under the menu.')
    t.append('- [x] Combat pace setting (Normal / Slow / Very slow, default Slow) keeps each combat step on screen longer.')
    t.append('- [x] Enlarged HUD buttons on big screens can be tapped over their whole drawn size.')
    t.append('- [ ] Check on a real Android phone: hand size, buttons and combat pace feel right.')
    t.append('')
    if BUGS.exists():
        t.append('## Your bug list (bugs.md)')
        t.append('')
        for line in BUGS.read_text(encoding='utf-8').splitlines():
            m = re.match(r'\s*\d+\s*[.,)]\s*(.*)', line)
            if m and m.group(1).strip():
                t.append(f'- [ ] {m.group(1).strip()}')
        t.append('')
    t.append('## Unverified (please check against your physical cards)')
    t.append('')
    for hid, text in SET_RULES.items():
        if 'UNVERIFIED' in text:
            name = next(h['name'] for h in heroes if h['id'] == hid)
            t.append(f'- [ ] {name}: {re.sub(r".*?UNVERIFIED[^:]*:\*\*\s*", "", text)}')
    t.extend(f'- [ ] {d}' for d in DECISIONS)
    t.append('')
    if todo:
        t.append('## Heroes not scripted yet')
        t.append('')
        for h in todo:
            t.extend(hero_checklist(h, False))
    t.append('## Heroes scripted (re-verify when touching their code)')
    t.append('')
    for h in done:
        t.extend(hero_checklist(h, True))
    (ROOT / 'CARD_TODO.md').write_text('\n'.join(t) + '\n', encoding='utf-8')
    print(f'Wrote CARDS.md and CARD_TODO.md: {len(heroes)} heroes, {len(done)} scripted.')


def hero_checklist(h, done):
    box = '[x]' if done else '[ ]'
    lines = [f'### {h["name"]} ({h["set"]})', '']
    fighters = '; '.join(f'{f["name"]} ×{f["count"]}: {f["hp"]} HP, {f["attack"]}' for f in h['fighters'])
    lines.append(f'- {box} Identity card: move {h["move"]}; {fighters}')
    name, text = ability_parts(h)
    lines.append(f'- {box} Special ability{" " + name if name else ""}: {cell(text)}')
    if h['id'] in SET_RULES:
        lines.append(f'- {box} Set rules: {SET_RULES[h["id"]]}')
    for c in h['cards']:
        bits = []
        if attack_value(c) != '—':
            bits.append(f'ATK {attack_value(c)}')
        if defense_value(c) != '—':
            bits.append(f'DEF {defense_value(c)}')
        bits.append(f'BOOST {boost_value(c)}')
        effects = [label.split(' (')[0] for key, label in SECTIONS if section_text(c, key)]
        if effects:
            bits.append(' + '.join(effects))
        lines.append(f'- {box} {c["title"]} ({TYPE_LABEL[c["type"]]}, ×{c["copies"]}): {", ".join(bits)}')
    lines.append('')
    return lines


if __name__ == '__main__':
    main()

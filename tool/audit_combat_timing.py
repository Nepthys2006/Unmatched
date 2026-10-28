import json
import os
import re
import glob
import sys
sys.stdout.reconfigure(encoding='utf-8')

_fold = {'Ö': 'O', 'ö': 'o', 'Ä': 'A', 'ä': 'a', 'Ü': 'U', 'ü': 'u', 'Æ': 'AE', 'æ': 'ae', 'Ð': 'D', 'ð': 'd', 'É': 'E', 'é': 'e'}

def norm_title(title):
    res = []
    for ch in title:
        res.append(_fold.get(ch, ch))
    s = "".join(res)
    s = re.sub(r"[‘’]", "'", s)
    s = re.sub(r'[“”]', '"', s)
    s = re.sub(r'[^ -~]', '', s)
    s = re.sub(r'\s+', ' ', s)
    return s.strip().upper()

heroes_file = 'assets/data/heroes.json'
with open(heroes_file, 'r', encoding='utf-8') as f:
    heroes = json.load(f)

dart_files = glob.glob('lib/engine/heroes/*.dart')
dart_sources = {df: open(df, 'r', encoding='utf-8').read() for df in dart_files}

def extract_card_script_block(content, title):
    for quote in ["'", '"']:
        target = f"{quote}{title}{quote}"
        idx = content.find(target)
        if idx != -1:
            # find CardScript( after target
            cs_idx = content.find("CardScript(", idx)
            if cs_idx != -1 and cs_idx - idx < 100:
                # Balance parens
                open_idx = cs_idx + len("CardScript(") - 1
                depth = 0
                for i in range(open_idx, len(content)):
                    if content[i] == '(':
                        depth += 1
                    elif content[i] == ')':
                        depth -= 1
                        if depth == 0:
                            return content[open_idx + 1:i]
    return None

total_cards = 0
mismatches = []
not_found = []

for h in heroes:
    hname = h.get('name')
    cards = h.get('cards', [])
    for c in cards:
        total_cards += 1
        raw_title = c.get('title', '')
        title = norm_title(raw_title)
        texts = c.get('text', {})
        if not texts:
            continue
        
        found_block = None
        for df, content in dart_sources.items():
            found_block = extract_card_script_block(content, title)
            if found_block is not None:
                break
        
        if found_block is None:
            # Check helper wrappers like valueIf or feint
            not_found.append((hname, title, list(texts.keys())))
            continue
        
        for timing in ['immediately', 'during', 'after']:
            if timing in texts:
                # check if timing keyword parameter exists in CardScript
                # e.g. "immediately:" or "during:" or "after:"
                has_param = re.search(rf"\b{timing}\s*:", found_block)
                if not has_param:
                    mismatches.append({
                        'hero': hname,
                        'card': title,
                        'timing': timing,
                        'text': texts[timing],
                        'block': found_block.strip()
                    })

print(f"Total cards: {total_cards}")
print(f"Cards not in standard CardScript( (helpers/custom): {len(not_found)}")
for nf in not_found:
    print(f"  Helper: {nf[0]} - {nf[1]} -> {nf[2]}")
print(f"\nReal timing mismatches found: {len(mismatches)}")
for m in mismatches:
    print(f"[{m['hero']}] '{m['card']}' -> text has '{m['timing']}' but script does not!")
    print(f"   Text: {m['text']}")
    print(f"   Script: {m['block'][:150]}")

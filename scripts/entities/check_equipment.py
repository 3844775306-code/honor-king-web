"""Cross-reference recommended build items against defined item IDs."""
import pathlib, re

path = pathlib.Path(r'C:\Users\18749\Documents\honor-king\assets\ItemDatabase.gd')
text = path.read_text('utf-8')

# Extract all defined item IDs (items["..."] = {)
defined = set(re.findall(r'items\["([^"]+)"\]\s*=', text))
print(f"Defined items: {len(defined)}")
print()

# Extract the get_recommended_items function body
idx = text.find('func get_recommended_items')
func_text = text[idx:]

# Extract all hero names and build arrays
# Pattern: "HeroName": [[...], [...], [...]],
hero_section = re.findall(r'"([^"]+)":\s*\[', func_text)
hero_names = set()
for h in hero_section:
    if not any(c in h for c in ['tier', 'class', 'name', 'requires', 'passive', 'active', 'skill', 'speed', 'attack', 'cooldown', 'health', 'mana', 'armor', 'magic', 'crit', 'lifesteal', 'spell_vamp', 'hp_regen', 'per_speed', 'ability_power']):
        hero_names.add(h)

# Remove role pool keys
role_keys = {'战士', '射手', '法师', '刺客', '辅助'}
hero_names -= role_keys
print(f"Heroes with builds: {len(hero_names)}")
for h in sorted(hero_names):
    print(f"  {h}")

# Extract all item IDs from builds (strings inside arrays that look like item IDs)
# Items are lowercase_with_underscores
item_pattern = re.compile(r'^[a-z][a-z0-9_]*$')
all_build_strings = set()
for match in re.finditer(r'"([^"]+)"', func_text):
    s = match.group(1)
    if item_pattern.match(s) and s not in hero_names and s not in role_keys:
        if s not in ['name', 'tier', 'class', 'requires', 'passive', 'active', 'skill']:
            all_build_strings.add(s)

# Cross-reference
missing = sorted([s for s in all_build_strings if s not in defined])
valid = sorted([s for s in all_build_strings if s in defined])

print(f"\n=== VALID items in builds ({len(valid)}) ===")
print()

print(f"=== MISSING items ({len(missing)}) ===")
for m in missing:
    # Find which heroes use this item
    users = []
    lines = func_text.split('\n')
    current_hero = None
    for line in lines:
        hm = re.match(r'^\s*"([^"]+)":\s*\[', line)
        if hm and hm.group(1) in hero_names:
            current_hero = hm.group(1)
        if f'"{m}"' in line and current_hero:
            users.append(current_hero)
    print(f"  '{m}' -> used by: {', '.join(sorted(set(users)))}")

if not missing:
    print("  None! All items exist.")

"""Fix non-existent equipment in recommended builds."""
import pathlib

path = pathlib.Path(r'C:\Users\18749\Documents\honor-king\assets\ItemDatabase.gd')
text = path.read_text('utf-8')

# Fix 1: magic_boots -> spell_boots
count1 = text.count('"magic_boots"')
text = text.replace('"magic_boots"', '"spell_boots"')
print(f"Fix 1: magic_boots -> spell_boots ({count1} occurrences)")

# Fix 2: speed_boots -> swift_boots
count2 = text.count('"speed_boots"')
text = text.replace('"speed_boots"', '"swift_boots"')
print(f"Fix 2: speed_boots -> swift_boots ({count2} occurrences)")

path.write_text(text, 'utf-8')
print("Done - ItemDatabase.gd updated")

import sys
import xml.etree.ElementTree as ET

# Register namespaces to preserve them correctly
ET.register_namespace('', "http://www.w3.org/2000/svg")
ET.register_namespace('xlink', "http://www.w3.org/1999/xlink")
ET.register_namespace('svg', "http://www.w3.org/2000/svg")

svg_file = '/Users/armandmgt/Projects/velo/public/icon.svg'

# Use a parser that preserves comments and namespaces if possible, 
# but standard ET is often safer for simple move.
tree = ET.parse(svg_file)
root = tree.getroot()

ns = {
    'svg': 'http://www.w3.org/2000/svg',
    'xlink': 'http://www.w3.org/1999/xlink'
}

# Find the <defs> element
defs = root.find('svg:defs', ns)
if defs is None:
    defs = ET.Element('{http://www.w3.org/2000/svg}defs')
    root.insert(0, defs)

# IDs of the groups to move to <defs>
ids_to_move = ['g85125', 'g85112', 'g85099', 'g85097']

for target_id in ids_to_move:
    # Find the element anywhere in the tree
    elem = root.find(f".//*[@id='{target_id}']")
    if elem is not None:
        # Find the parent of the element
        # We need to find the actual parent to remove it
        # ET doesn't have a direct 'getparent' but we can find it
        parent = None
        for p in root.iter():
            if elem in list(p):
                parent = p
                break
        
        if parent is not None:
            parent.remove(elem)
            defs.append(elem)
            print(f"Moved element with id='{target_id}' from '{parent.tag}' to 'defs'")
        else:
            print(f"Parent for '{target_id}' not found, maybe already in defs?")
    else:
        print(f"Element with id='{target_id}' not found")

# Save the result
# Using a custom writer to try and preserve as much as possible, or just standard write
tree.write(svg_file, encoding='UTF-8', xml_declaration=True)

import sys

filename = "/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/Views/FrenchRetroSmallWorldView.swift"

with open(filename, 'r') as f:
    lines = f.readlines()

count = 0
for i, line in enumerate(lines):
    line_num = i + 1
    # Ignore comments
    code = line.split('//')[0]
    
    open_braces = code.count('{')
    close_braces = code.count('}')
    
    count += open_braces
    count -= close_braces
    
    if count < 0:
        print(f"Extra closing brace found at line {line_num}: {line.strip()}")
        break
    
    if count == 0 and i < len(lines) - 100: # Assuming file is long enough
        # If count reaches 0 too early (before end of file), that's where struct ends prematurely
        # But we need to distinguish between struct end and other blocks
        pass

print(f"Final count: {count}")

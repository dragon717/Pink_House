filename = "/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/Views/FrenchRetroSmallWorldView.swift"

with open(filename, 'r') as f:
    lines = f.readlines()

count = 0
for i, line in enumerate(lines):
    line_num = i + 1
    code = line.split('//')[0]
    
    open_braces = code.count('{')
    close_braces = code.count('}')
    
    count += open_braces
    count -= close_braces
    
    if count < 0:
        print(f"Extra closing brace found at line {line_num}: {line.strip()}")
        break

if count == 0:
    print("Braces are balanced.")
else:
    print(f"Braces are unbalanced. Final count: {count}")

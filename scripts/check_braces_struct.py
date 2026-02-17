filename = "/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/Views/FrenchRetroSmallWorldView.swift"

with open(filename, 'r') as f:
    lines = f.readlines()

count = 0
struct_closed = False

for i, line in enumerate(lines):
    line_num = i + 1
    code = line.split('//')[0]
    
    open_braces = code.count('{')
    close_braces = code.count('}')
    
    count += open_braces
    count -= close_braces
    
    if count == 0 and not struct_closed:
        print(f"Struct potentially closed at line {line_num}: {line.strip()}")
        struct_closed = True
    elif count < 0:
        print(f"Extra closing brace found at line {line_num}: {line.strip()}")
        break


import sys

def patch_file(filepath, target, replacement):
    with open(filepath, 'r', encoding='utf-8', newline='') as f:
        content = f.read()
    
    # Try exact match first
    if target in content:
        new_content = content.replace(target, replacement, 1)
    else:
        # Try normalizing newlines
        c_norm = content.replace('\r\n', '\n')
        t_norm = target.replace('\r\n', '\n')
        r_norm = replacement.replace('\r\n', '\n')
        if t_norm in c_norm:
            c_norm = c_norm.replace(t_norm, r_norm, 1)
            # detect original newline
            nl = '\r\n' if '\r\n' in content else '\n'
            new_content = c_norm.replace('\n', nl)
        else:
            raise ValueError(f"Target string not found in {filepath}!")

    with open(filepath, 'w', encoding='utf-8', newline='') as f:
        f.write(new_content)
    print(f"Successfully patched {filepath}")

if __name__ == '__main__':
    pass

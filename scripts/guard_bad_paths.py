#!/usr/bin/env python3
import os
import re
import sys
from pathlib import Path

PATTERNS = [
    r'[^\x20-\x7E]{5,}',
    r'[\x00-\x08\x0B-\x0C\x0E-\x1F\x7F]',
    r'\\',
    r'//',
]

def has_issues(content):
    for pattern in PATTERNS:
        if re.search(pattern, content):
            return True
    return False

def clean_file(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()

        if not has_issues(content):
            return False

        content = re.sub(r'[\x00-\x08\x0B-\x0C\x0E-\x1F\x7F]', '', content)
        content = re.sub(r'\\+', '\\', content)
        content = re.sub(r'//+', '//', content)

        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        return True
    except:
        return False

def should_check(filepath):
    skip = {'.git', '_build', 'node_modules', '__pycache__'}
    exts = {'.git', '.png', '.jpg', '.jpeg', '.wasm', '.core', '.map'}
    filepath = Path(filepath)

    for part in filepath.parts:
        if part in skip:
            return False

    if filepath.suffix in exts:
        return False

    if not filepath.is_file():
        return False

    if filepath.stat().st_size > 1024 * 1024:
        return False

    return True

def main():
    project_root = Path(__file__).parent.parent
    fixed = 0

    print(f"Scanning: {project_root}")

    for root, dirs, files in os.walk(project_root):
        dirs[:] = [d for d in dirs if d not in {'.git', '_build', 'node_modules', '__pycache__'}]

        for filename in files:
            filepath = Path(root) / filename

            if not should_check(filepath):
                continue

            if clean_file(filepath):
                print(f"Fixed: {filepath.relative_to(project_root)}")
                fixed += 1

    print(f"Files fixed: {fixed}")
    return 0

if __name__ == '__main__':
    sys.exit(main())
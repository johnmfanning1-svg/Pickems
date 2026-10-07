#!/usr/bin/env python3
"""Flag SwiftUI presentation modifiers attached to List/Form rows or Sections.

A .sheet/.alert/.fullScreenCover/.confirmationDialog/.popover chained onto a
Section, ForEach, or a computed `...Section`/`...Row` view is hosted by a lazily
recycled List cell; Firestore/timer updates tear it down and UIKit dismisses
whatever is presented (see docs/PRESENTATIONS.md).
"""
import re, sys, pathlib

MOD = re.compile(r'^\s*\.(sheet|alert|fullScreenCover|confirmationDialog|popover)\(')
BAD_HEAD = re.compile(r'^\s*(Section\b|ForEach\b|[a-z]\w*(Section|Row|Rows)\b\s*$)')
ALLOW = 'presentation-ok'
COMPONENT = re.compile(r'^\s*(?:private\s+|fileprivate\s+)?struct\s+(\w+(Button|Row|Card|Cell|Board|Banner|Chip))\b[^{]*:\s*View')
SHARED = re.compile(r'(\$viewModel\.|\$appState\.|appState\.picksViewModel\.|\$picksVM\.)')
HOST_FILES = ('AppSheetHost.swift',)  # put `// presentation-ok: <reason>` on the modifier line to waive

def heads(lines, i):
    bal = 0
    for j in range(i - 1, -1, -1):
        s = re.sub(r'"(\\.|[^"\\])*"', '""', lines[j].split('//')[0])
        bal += s.count('}') + s.count(')') - s.count('{') - s.count('(')
        st = s.strip()
        if not st:
            continue
        if bal <= 0 and not st.startswith(('.', '}', ')', '#')):
            return j
    return None

def main(root):
    bad = []
    for p in sorted(pathlib.Path(root).rglob('*.swift')):
        lines = p.read_text().splitlines()
        comp = None
        for i, line in enumerate(lines):
            m = re.match(r'^\s*(?:private\s+|fileprivate\s+)?struct\s+(\w+)', line)
            if m:
                comp = m.group(1) if COMPONENT.match(line) else None
            if not MOD.match(line) or ALLOW in line or p.name in HOST_FILES:
                continue
            where = f'{p}:{i+1}: {line.strip()[:60]}'
            h = heads(lines, i)
            if h is not None and BAD_HEAD.match(lines[h]):
                bad.append(f'{where}  <- attached to `{lines[h].strip()[:40]}` (line {h+1}) inside a List/Form')
            elif comp:
                bad.append(f'{where}  <- owned by reusable component `{comp}`; route through the screen presenter')
            elif SHARED.search(line):
                bad.append(f'{where}  <- bound to shared app/view-model state; use local @State or the host enum')
    for b in bad:
        print(b)
    if bad:
        print(f'\n{len(bad)} presentation(s) break the app presentation rules. '
              'See docs/PRESENTATIONS.md (or add // presentation-ok: <reason> after review).', file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else 'Pickems'))

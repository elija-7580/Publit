#!/usr/bin/env python3
"""List the Swift files of a project.yml target (directories expanded), one per line.

Usage: target_files.py <repo root> <target>   (needs PyYAML)
Used by .github/workflows/watch.yml to type-check a target quickly, without building the whole app.
"""
import sys, os, yaml
root = sys.argv[1]; target = sys.argv[2]
p = yaml.safe_load(open(os.path.join(root, 'project.yml')))
srcs = p['targets'][target]['sources']
out = []
for s in srcs:
    path = s['path'] if isinstance(s, dict) else s
    full = os.path.join(root, path)
    if os.path.isdir(full):
        for d, _, fs in os.walk(full):
            for f in fs:
                if f.endswith('.swift'): out.append(os.path.join(d, f))
    elif full.endswith('.swift'):
        out.append(full)
for f in sorted(out): print(f)

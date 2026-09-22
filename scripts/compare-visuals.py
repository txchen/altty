#!/usr/bin/env python3
"""Compare reviewed AppKit PNG baselines. Never creates/updates accepted images."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops

parser = argparse.ArgumentParser()
parser.add_argument('baseline', type=Path)
parser.add_argument('actual', type=Path)
parser.add_argument('--max-changed-fraction', type=float, default=0.001)
args = parser.parse_args()
expected = {p.name for p in args.baseline.glob('*.png')}
actual = {p.name for p in args.actual.glob('*.png')}
if not expected or expected != actual:
    raise SystemExit(f'Image set mismatch: missing={sorted(expected-actual)}, extra={sorted(actual-expected)}; baseline must exist')
failures = []
for name in sorted(expected):
    before = Image.open(args.baseline / name).convert('RGBA')
    after = Image.open(args.actual / name).convert('RGBA')
    if before.size != after.size:
        failures.append({'image': name, 'reason': 'size changed'})
        continue
    diff = ImageChops.difference(before, after)
    # Allow tiny antialiasing noise, but count changes in ANY channel, including alpha.
    changed = sum(max(pixel) > 8 for pixel in diff.getdata())
    fraction = changed / (before.width * before.height)
    if fraction > args.max_changed_fraction:
        failures.append({'image': name, 'changed_fraction': fraction})
        diff.save(args.actual / (name + '.diff.png'))
report = {'images': len(expected), 'failures': failures}
(args.actual / 'comparison.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
raise SystemExit(bool(failures))

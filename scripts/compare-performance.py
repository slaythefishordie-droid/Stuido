#!/usr/bin/env python3
"""Compare like-for-like synthetic samples; never reports device FPS/energy."""
import json
import math
import statistics
import sys
from pathlib import Path

before = json.loads(Path(sys.argv[1]).read_text())
after = json.loads(Path(sys.argv[2]).read_text())
assert before['configuration'] == after['configuration'] == 'Release'
assert before.get('fixture_version') == after.get('fixture_version') == 2, 'Incompatible fixture version'
assert len(before['datasets']) == len(after['datasets'])
print('| Cards | Operation | Baseline median ms | Optimized median ms |')
print('|---:|---|---:|---:|')
for old, new in zip(before['datasets'], after['datasets']):
    for key in ['cards', 'sources', 'marks', 'snapshot_bytes']:
        assert old[key] == new[key], f'Fixture changed: {key}'
    for name, original in old['metrics'].items():
        current = new['metrics'][name]
        assert original['checksum'] == current['checksum'], f'Result changed: {name}'
        for metric in [original, current]:
            samples = metric['samples_ms']
            assert len(samples) == before['iterations'] == after['iterations']
            assert all(math.isfinite(x) and x >= 0 for x in samples)
            assert statistics.median(samples) == metric['median_ms']
            assert max(samples) == metric['max_ms']
        print(f"| {old['cards']} | {name} | {original['median_ms']:.3f} | {current['median_ms']:.3f} |")
    indexed = new['metrics'].get('indexed_marks_for_100_sources')
    if indexed:
        assert indexed['checksum'] == old['metrics']['marks_for_100_sources']['checksum']
        print(f"| {old['cards']} | indexed_marks_for_100_sources | {old['metrics']['marks_for_100_sources']['median_ms']:.3f} | {indexed['median_ms']:.3f} |")

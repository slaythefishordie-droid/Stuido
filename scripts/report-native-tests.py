#!/usr/bin/env python3
"""Expose bounded diagnostics even if xcodebuild exits before its summary command.

The complete log/xcresult remains an artifact. The check annotations can be read
through GitHub's API when the artifact's storage hostname is unavailable.
"""
import json
import subprocess
from pathlib import Path


def annotate(level, text):
    text = str(text).replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    print(f'::{level}::{text[:6000]}')


def linker_context(lines):
    blocks = []
    for index, line in enumerate(lines):
        if 'undefined symbols for architecture' not in line.lower():
            continue
        block = []
        for item in lines[index:index + 100]:
            block.append(item)
            if 'symbol(s) not found' in item.lower():
                break
        blocks.extend('\n'.join(block[start:start + 12]) for start in range(0, len(block), 12))
    return blocks[:12]


def main():
    root = Path('artifacts')
    bundle = root / 'SimulatorTests.xcresult'
    if bundle.exists():
        result = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                 '--path', str(bundle), '--format', 'json'], capture_output=True, text=True)
        if result.returncode == 0:
            summary = json.loads(result.stdout)
            (root / 'simulator-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
            counts = {key: summary.get(key) for key in
                      ['title', 'result', 'totalTestCount', 'passedTests', 'failedTests', 'skippedTests']}
            annotate('notice', 'Native test summary: ' + json.dumps(counts, ensure_ascii=False))
            for failure in (summary.get('testFailures') or [])[:20]:
                annotate('error', json.dumps(failure, ensure_ascii=False))
        else:
            annotate('warning', 'xcresult summary unavailable: ' + result.stderr[-3000:])
    log = root / 'logs/simulator-tests.log'
    if not log.exists():
        return
    lines = log.read_text(errors='replace').splitlines()
    for block in linker_context(lines):
        annotate('error', 'Linker symbols:\n' + block)
    failures = [line for line in lines if any(term in line.lower() for term in
                ['error:', ' failed', 'testing failed', 'timed out', 'crashed', 'unable to', '** test'])]
    for line in failures[-15:]:
        annotate('notice' if '** TEST SUCCEEDED **' in line else 'warning', line)
    # A simulator launch/transport failure may have no XCTest assertion. Retain
    # its terminal context rather than annotating unrelated plist build commands.
    if not any('** TEST SUCCEEDED **' in line for line in lines):
        annotate('warning', 'Native log tail:\n' + '\n'.join(lines[-25:]))


if __name__ == '__main__':
    main()

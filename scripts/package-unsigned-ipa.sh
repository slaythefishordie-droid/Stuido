#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ks_app="$PWD/.build/KnowledgeStudio.xcarchive/Products/Applications/KnowledgeStudio.app"
test -d "$ks_app"
ks_binary="$ks_app/$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$ks_app/Info.plist")"
xcrun lipo -verify_arch arm64 "$ks_binary"
xcrun vtool -show-build "$ks_binary" > .build/device-platform.txt
python3 - "$ks_app" <<'PY'
import pathlib, plistlib, re, sys
app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info.get('CFBundlePackageType') == 'APPL', 'Not an application bundle'
assert info.get('CFBundleSupportedPlatforms') == ['iPhoneOS'], 'Simulator output is not an iPadOS IPA'
assert 2 in info.get('UIDeviceFamily', []), 'App must support iPad'
build = pathlib.Path('.build/device-platform.txt').read_text()
assert re.search(r'platform\s+IOS\s*$', build, re.M), 'Mach-O is not built for iOS devices'
assert not (app / 'embedded.mobileprovision').exists(), 'Unexpected provisioning profile'
assert not (app / '_CodeSignature').exists(), 'Expected an unsigned device archive'
PY
ks_staging=$(mktemp -d "$PWD/.build/ipa-staging.XXXXXX")
trap 'rm -rf "$ks_staging"' EXIT
mkdir -p "$ks_staging/Payload" artifacts
ditto "$ks_app" "$ks_staging/Payload/KnowledgeStudio.app"
ks_output="$PWD/artifacts/KnowledgeStudio-unsigned.ipa"
(cd "$ks_staging" && ditto -c -k --keepParent Payload "$ks_output")
unzip -t "$ks_output"
shasum -a 256 "$ks_output" > artifacts/KnowledgeStudio-unsigned.ipa.sha256
python3 - <<'PY'
import json, os, pathlib, zipfile
path = pathlib.Path('artifacts/KnowledgeStudio-unsigned.ipa')
with zipfile.ZipFile(path) as archive:
    assert 'Payload/KnowledgeStudio.app/Info.plist' in archive.namelist()
    assert archive.testzip() is None
report = {
    'commit': os.environ.get('GITHUB_SHA', 'local'),
    'build_type': 'Release iphoneos arm64',
    'device_compilation': 'passed',
    'package_structure': 'verified',
    'signed': False,
    'requires_resigning': True,
    'altstore_installation': 'not_tested',
    'physical_ipad_validation': 'not_tested',
    'note': 'Unsigned IPA candidate for AltStore Classic; packaging is not proof of successful installation.'
}
pathlib.Path('artifacts/package-report.json').write_text(json.dumps(report, indent=2) + '\n')
PY

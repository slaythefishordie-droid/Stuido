#!/usr/bin/env bash
set -euo pipefail
trap 'ks_exit=$?; printf "::error title=IPA packaging command failed::Line %s exited with status %s\n" "$LINENO" "$ks_exit"; exit "$ks_exit"' ERR
cd "$(dirname "$0")/.."
fail() {
  printf '::error title=IPA package validation::%s\n' "$1"
  exit 1
}
ks_app="$PWD/.build/KnowledgeStudio.xcarchive/Products/Applications/KnowledgeStudio.app"
test -d "$ks_app" || fail 'The device archive does not contain Products/Applications/KnowledgeStudio.app.'
ks_binary="$ks_app/$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$ks_app/Info.plist")"
test -f "$ks_binary" || fail 'The App executable declared by Info.plist is missing.'
# lipo consumes every argument after -verify_arch as an architecture name.
# The input file must precede -verify_arch (Apple cctools misc/lipo.c).
xcrun lipo "$ks_binary" -verify_arch arm64 || fail 'The device App does not contain the required arm64 architecture.'
xcrun vtool -show-build "$ks_binary" > .build/device-platform.txt || fail 'Unable to inspect the device Mach-O build platform.'
python3 - "$ks_app" <<'PY'
import pathlib, plistlib, re, sys
def require(condition, message):
    if not condition:
        escaped = message.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
        print(f'::error title=IPA package validation::{escaped}')
        raise SystemExit(1)
app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app / 'Info.plist').read_bytes())
require(info.get('CFBundlePackageType') == 'APPL', f"Not an application bundle: {info.get('CFBundlePackageType')}")
require(info.get('CFBundleSupportedPlatforms') == ['iPhoneOS'], f"Expected iPhoneOS, got {info.get('CFBundleSupportedPlatforms')}; simulator output cannot become an iPadOS IPA")
require(2 in info.get('UIDeviceFamily', []), f"App must support iPad; got device family {info.get('UIDeviceFamily')}")
build = pathlib.Path('.build/device-platform.txt').read_text()
require(re.search(r'platform\s+IOS\s*$', build, re.M), f'Mach-O is not built for iOS devices: {build[:500]}')
require(not (app / 'embedded.mobileprovision').exists(), 'Unexpected provisioning profile')
require(not (app / '_CodeSignature').exists(), 'Expected an unsigned device archive')
PY
ks_extension="$ks_app/PlugIns/SafariExtension.appex"
test -d "$ks_extension" || fail 'Safari extension is missing from the device archive.'
ks_extension_binary="$ks_extension/$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$ks_extension/Info.plist")"
xcrun lipo "$ks_extension_binary" -verify_arch arm64
xcrun vtool -show-build "$ks_extension_binary" > .build/extension-platform.txt
python3 - "$ks_extension" <<'CHECK'
import pathlib, plistlib, re, sys
extension = pathlib.Path(sys.argv[1])
info = plistlib.loads((extension / 'Info.plist').read_bytes())
assert info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.Safari.web-extension'
assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
assert re.search(r'platform\s+IOS\s*$', pathlib.Path('.build/extension-platform.txt').read_text(), re.M)
assert (extension / 'Resources/manifest.json').is_file()
CHECK
# Ad-hoc signatures carry requested entitlements for the user's re-signing tool.
# They do not provide an Apple provisioning profile or grant device permissions.
codesign --force --sign - --generate-entitlement-der --entitlements ios/SafariExtension/SafariExtension.entitlements "$ks_extension"
codesign --force --sign - --generate-entitlement-der --entitlements ios/KnowledgeStudio/KnowledgeStudio.entitlements "$ks_app"
codesign --verify --deep --strict "$ks_app"
codesign -d --entitlements :- "$ks_app" > .build/app-entitlements.plist
codesign -d --entitlements :- "$ks_extension" > .build/extension-entitlements.plist
python3 - <<'CHECK'
import plistlib, pathlib
for name in ['app', 'extension']:
    entitlements = plistlib.loads(pathlib.Path(f'.build/{name}-entitlements.plist').read_bytes())
    assert entitlements['com.apple.security.application-groups'] == ['group.org.knowledge-studio.prototype']
CHECK
ks_staging=$(mktemp -d "$PWD/.build/ipa-staging.XXXXXX")
trap 'rm -rf "$ks_staging"' EXIT
mkdir -p "$ks_staging/Payload" artifacts
ditto "$ks_app" "$ks_staging/Payload/KnowledgeStudio.app"
ks_output="$PWD/artifacts/KnowledgeStudio-resignable.ipa"
(cd "$ks_staging" && ditto -c -k --keepParent Payload "$ks_output")
unzip -t "$ks_output"
(cd artifacts && shasum -a 256 KnowledgeStudio-resignable.ipa > KnowledgeStudio-resignable.ipa.sha256)
python3 - "$ks_app" <<'PY'
import json, os, pathlib, plistlib, sys, zipfile
path = pathlib.Path('artifacts/KnowledgeStudio-resignable.ipa')
info = plistlib.loads((pathlib.Path(sys.argv[1]) / 'Info.plist').read_bytes())
with zipfile.ZipFile(path) as archive:
    assert 'Payload/KnowledgeStudio.app/Info.plist' in archive.namelist()
    assert archive.testzip() is None
report = {
    'commit': os.environ.get('GITHUB_SHA', 'local'),
    'build_type': 'Release iphoneos arm64',
    'device_compilation': 'passed',
    'package_structure': 'verified',
    'signed': True,
    'signing': 'ad-hoc; user provisioning required',
    'safari_extension_embedded': True,
    'requested_app_group': 'group.org.knowledge-studio.prototype',
    'safari_recognition': 'not_tested',
    'app_group_sharing': 'not_tested',
    'requires_resigning': True,
    'bundle_identifier': info['CFBundleIdentifier'],
    'minimum_os_version': info['MinimumOSVersion'],
    'sdk': info.get('DTSDKName'),
    'device_family': info['UIDeviceFamily'],
    'altstore_installation': 'not_tested',
    'physical_ipad_validation': 'not_tested',
    'note': 'Ad-hoc IPA for AltStore Classic re-signing; device extension and App Groups permissions require verification.'
}
pathlib.Path('artifacts/package-report.json').write_text(json.dumps(report, indent=2) + '\n')
PY

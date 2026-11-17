#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(uname -s)" = Darwin || { echo 'XcodeGen binary requires macOS.' >&2; exit 1; }
mkdir -p .build/tools
ks_archive="$PWD/.build/tools/xcodegen-2.44.1.zip"
curl --fail --location --retry 2 --silent --show-error \
  https://github.com/yonaskolb/XcodeGen/releases/download/2.44.1/xcodegen.zip -o "$ks_archive"
# Digest published in the official release metadata; verification must not be disabled.
printf '%s  %s\n' 'a2e905fb68446e9bb4008cdfe2e13e3f176d0cbcca828b71770f8e53fca91b73' "$ks_archive" | shasum -a 256 -c -
unzip -oq "$ks_archive" -d .build/tools
.build/tools/xcodegen/bin/xcodegen --version
.build/tools/xcodegen/bin/xcodegen generate --spec ios/project.yml
mkdir -p ios/KnowledgeStudio.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp ios/Package.resolved ios/KnowledgeStudio.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

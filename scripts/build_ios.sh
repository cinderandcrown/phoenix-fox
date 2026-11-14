#!/usr/bin/env bash
# Generic iOS build helper. Examples:
#   PROJECT=MyApp.xcodeproj SCHEME=MyApp bash scripts/build_ios.sh
#   WORKSPACE=MyApp.xcworkspace SCHEME=MyApp bash scripts/build_ios.sh
set -euo pipefail
: "${SCHEME:?Set SCHEME to the actual shared Xcode scheme (use xcodebuild -list).}"
if [[ -n "${WORKSPACE:-}" ]]; then
  selection=(-workspace "$WORKSPACE")
elif [[ -n "${PROJECT:-}" ]]; then
  selection=(-project "$PROJECT")
else
  echo 'Set PROJECT=...xcodeproj or WORKSPACE=...xcworkspace' >&2
  exit 2
fi
mkdir -p .build
set -o pipefail
xcodebuild "${selection[@]}" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$PWD/.build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO build

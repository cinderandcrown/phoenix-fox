#!/usr/bin/env bash
set -uo pipefail

headline() { printf '\n\033[1m%s\033[0m\n' "$1"; }
check() {
  local label="$1"; shift
  printf '%-23s' "$label"
  if command -v "$1" >/dev/null 2>&1; then
    "$@" 2>&1 | head -n 3
  else
    printf 'NOT INSTALLED: %s\n' "$1"
  fi
}

headline 'Meta Glasses Swift — macOS environment doctor'
if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'WARNING: Not macOS. Xcode, Simulator and physical iOS builds require a Mac.\n'
fi
check 'Git' git --version
check 'GitHub CLI' gh --version
check 'Homebrew' brew --version
check 'Xcode CLI selector' xcode-select -p
check 'Xcode' xcodebuild -version
check 'Swift' swift --version
check 'SwiftLint' swiftlint version
check 'SwiftFormat' swiftformat --version
check 'XcodeGen (optional)' xcodegen --version
check 'xcbeautify (optional)' xcbeautify --version
check 'jq (optional)' jq --version
check 'Node (optional)' node --version

headline 'Simulator runtimes'
if command -v xcrun >/dev/null 2>&1; then
  xcrun simctl list devices available 2>&1 | head -n 35 || true
else
  echo 'xcrun not available'
fi
headline 'GitHub authentication'
if command -v gh >/dev/null 2>&1; then gh auth status 2>&1 | head -n 8 || true; else echo 'gh not available'; fi
headline 'Official Meta skill sync'
if [[ -f '.agents/skills/meta-official-getting-started/SKILL.md' ]]; then
  echo 'Found synced official Meta getting-started skill.'
else
  echo 'Not synced yet. Run: bash scripts/setup_mac.sh'
fi
headline 'Notes'
echo 'If Xcode is missing, install it using Apple’s official Xcode distribution, open it once, and accept required components.'
echo 'Xcode 26.4+, Swift 6.3+, and iOS 17.2+ match current official Meta sample requirements (verify current docs).'
echo 'The doctor does not install software or modify settings.'

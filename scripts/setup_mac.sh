#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/.vendor/meta-wearables-dat-ios"
TARGET="$ROOT/.agents/skills"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'This setup script targets macOS. Run it on the development Mac.' >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  echo 'Install Apple Command Line Tools (xcode-select --install) or Git first.' >&2
  exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo 'Xcode must be installed from Apple; this script will not install it or accept licenses.' >&2
  exit 1
fi
mkdir -p "$ROOT/.vendor" "$TARGET"

# Skills live on the default branch under plugins/mwdat-ios/skills. Tagged SDK
# releases (e.g. 1.0.1) ship binaries only and omit that path — always sync from
# the tip of main for skills. Do NOT commit .agents/skills/meta-official-* or
# .vendor/: Meta Wearables Developer Terms disallow redistributing the SDK.
if [[ ! -d "$VENDOR/.git" ]]; then
  echo 'Fetching Meta official DAT SDK docs and AI skills from public GitHub...'
  git clone --depth 1 --branch main https://github.com/meta/meta-wearables-dat-ios.git "$VENDOR"
else
  echo 'Updating official Meta docs/skills checkout (fast-forward only)...'
  git -C "$VENDOR" fetch --depth 1 origin main
  git -C "$VENDOR" checkout -B main origin/main
fi

SOURCE="$VENDOR/plugins/mwdat-ios/skills"
if [[ ! -d "$SOURCE" ]]; then
  echo "Official Meta skills path missing: $SOURCE (check repo layout)" >&2
  exit 1
fi
count=0
for skill in "$SOURCE"/*; do
  [[ -d "$skill" && -f "$skill/SKILL.md" ]] || continue
  name="$(basename "$skill")"
  dest="$TARGET/meta-official-$name"
  mkdir -p "$dest"
  # rsync is preinstalled on macOS; intentionally refreshes only our own prefixed directories.
  rsync -a --delete "$skill/" "$dest/"
  count=$((count+1))
done
printf 'Synced %s official Meta skills to .agents/skills/meta-official-*/ (gitignored; regenerate locally or via CI)\n' "$count"
printf 'Pinned app SDK remains 1.0.1 via Package.resolved (SHA 0bd369298eef6a980ad0bdb6c8a5502f2c02a08c).\n'

# Optional package manager tools (explicit opt-in only).
if [[ "${1:-}" == '--install-tools' ]]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo 'Homebrew not found. Install from https://brew.sh/ after reviewing instructions; no remote script is auto-executed.' >&2
    exit 1
  fi
  echo 'Installing optional developer tooling with Homebrew...'
  brew install git gh jq ripgrep swiftlint swiftformat xcodegen xcbeautify
else
  echo 'To install optional tools: bash scripts/setup_mac.sh --install-tools (requires preinstalled Homebrew).'
fi

echo 'Next: bash scripts/doctor_mac.sh; then inspect the official CameraAccess sample and your app project.'
echo 'If you use Grok, explicitly instruct it to read AGENTS.md and SKILL.md; Grok skill auto-discovery is not assumed.'

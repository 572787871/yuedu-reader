#!/bin/bash
# resign_ipa.sh — re-sign the unsigned YueduReader IPA for real-device sideloading.
#
# The CI artifact "YueduReader-unsigned.ipa" is built with CODE_SIGNING_ALLOWED=NO,
# so it has NO valid code signature. A non-jailbroken iPhone/iPad will kill the app
# at launch (it shows as an instant crash / "打开闪退"). This script re-signs the
# app with YOUR OWN signing identity + provisioning profile so it can actually run.
#
# You need a Mac with Xcode command-line tools installed.
#
# Usage:
#   ./scripts/resign_ipa.sh \
#       --ipa YueduReader-unsigned.ipa \
#       --identity "Apple Development: you@example.com (XXXXXX)" \
#       --profile "YueduReader_Development.mobileprovision" \
#       [--bundle-id "com.yourorg.yuedureader"]
#
# Get your signing identity with:  security find-identity -v -p codesigning
# Get a provisioning profile from Xcode:
#   Signing & Capabilities → add your Apple ID → enable "Automatically manage signing"
#   → pick a free/paid team → Xcode creates a profile for the app's bundle id.
#   The profile is usually at ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision
#
# For the simplest path with NO Mac and NO paid cert, use a sideload tool instead:
#   Sideloadly (Windows/macOS, uses a free Apple ID, 7-day cert)
#   AltStore (requires AltServer)
#   Feather (uses a cert you provide)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$SCRIPT_DIR/.resign_work"

IPA=""
IDENTITY=""
PROFILE=""
BUNDLE_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ipa) IPA="$2"; shift 2 ;;
    --identity) IDENTITY="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$IPA" || -z "$IDENTITY" || -z "$PROFILE" ]]; then
  echo "Usage: resign_ipa.sh --ipa <file.ipa> --identity <codesign id> --profile <file.mobileprovision> [--bundle-id <id>]" >&2
  exit 2
fi

command -v codesign >/dev/null 2>&1 || { echo "codesign not found (need macOS + Xcode CLT)." >&2; exit 1; }
command -v security >/dev/null 2>&1 || { echo "security not found (need macOS)." >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK"

echo "==> Unzipping $IPA"
unzip -q -o "$IPA" -d "$WORK"
APP=$(find "$WORK/Payload" -maxdepth 1 -name '*.app' | head -1)
[[ -n "$APP" ]] || { echo "No .app found in IPA" >&2; exit 1; }

echo "==> Installing provisioning profile"
cp "$PROFILE" "$APP/embedded.mobileprovision"

if [[ -n "$BUNDLE_ID" ]]; then
  echo "==> Rewriting bundle id -> $BUNDLE_ID"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Info.plist"
  # Update any *.appex bundle ids so they stay in the same App Group namespace.
  for ext in "$APP/PlugIns"/*.appex; do
    [[ -e "$ext/Info.plist" ]] || continue
    base="$BUNDLE_ID.$(basename "$ext" .appex)"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $base" "$ext/Info.plist"
  done
fi

echo "==> Fixing extended attributes"
# Strip xattr quarantine/com.apple.quarantine that can make codesign complain.
xattr -cr "$APP" 2>/dev/null || true

echo "==> Re-signing frameworks / appex / app"
# 1) Sign nested code (frameworks, extensions) first, deepest first.
find "$APP" -type d \( -name '*.framework' -o -name '*.appex' -o -name 'Frameworks' \) | while read -r item; do
  if [[ -d "$item" ]]; then
    codesign --force --timestamp=none --sign "$IDENTITY" "$item" 2>/dev/null || true
  fi
done
# 2) Sign top-level frameworks.
if [[ -d "$APP/Frameworks" ]]; then
  for fw in "$APP/Frameworks"/*; do
    [[ -e "$fw" ]] || continue
    codesign --force --timestamp=none --sign "$IDENTITY" "$fw"
  done
fi
# 3) Sign the app itself.
codesign --force --timestamp=none --sign "$IDENTITY" --entitlements <( \
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>get-task-allow</key><false/></dict></plist>\n' \
) "$APP"

echo "==> Verifying signature"
codesign --verify --strict --verbose=2 "$APP"

OUT="${IPA%.ipa}-signed.ipa"
echo "==> Zipping signed IPA -> $OUT"
( cd "$WORK" && zip -q -r -y "$OUT" Payload )
# Move the resulting IPA next to the source.
if [[ -f "$WORK/$OUT" ]]; then
  mv "$WORK/$OUT" "$(dirname "$IPA")/$OUT"
else
  # zip wrote relative path; rebuild from WORK.
  ( cd "$WORK" && zip -q -r -y "$(dirname "$IPA")/$OUT" Payload )
fi

echo "==> Signed IPA ready: $(dirname "$IPA")/$OUT"
echo "    Install with Sideloadly / AltStore / Apple Configurator (free Apple ID works)."

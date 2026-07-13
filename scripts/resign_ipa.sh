#!/usr/bin/env bash
# resign_ipa.sh — re-sign the unsigned YueduReader IPA for real-device sideloading.
#
# The CI artifact "YueduReader-unsigned.ipa" is built with CODE_SIGNING_ALLOWED=NO,
# so it has NO valid code signature. A non-jailbroken iPhone/iPad will kill the app
# at launch (it shows as an instant crash / "打开闪退"). This script re-signs the
# app with YOUR OWN signing identity + provisioning profile so it can actually run.
#
# Key fix: the app needs its REAL entitlements (iCloud, App Groups, Sign in with Apple)
# extracted from the provisioning profile — NOT a hardcoded minimal plist.
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
#   Signing & Capabilities -> add your Apple ID -> enable "Automatically manage signing"
#   -> pick a free/paid team -> Xcode creates a profile for the app's bundle id.
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
command -v PlistBuddy >/dev/null 2>&1 || { echo "PlistBuddy not found (need macOS)." >&2; exit 1; }

# Path for extracted entitlements
ENTITLEMENTS_PLIST="$WORK/extracted-entitlements.plist"

rm -rf "$WORK"
mkdir -p "$WORK"

echo "==> Unzipping $IPA"
unzip -q -o "$IPA" -d "$WORK"
APP=$(find "$WORK/Payload" -maxdepth 1 -name '*.app' | head -1)
[[ -n "$APP" ]] || { echo "No .app found in IPA" >&2; exit 1; }
APEX_DIR="$APP/PlugIns"

# --- Extract REAL entitlements from the provisioning profile ---
# The old version used a hardcoded minimal entitlement (get-task-allow=false).
# That caused instant crash because iCloud, App Groups, and Sign in with Apple
# entitlements were missing — iOS kills the app when entitlements mismatch.
echo "==> Extracting entitlements from provisioning profile..."
if ! security cms -D -i "$PROFILE" 2>/dev/null | \
     PlistBuddy -c "Print :Entitlements" -x /dev/stdin 2>/dev/null > "$ENTITLEMENTS_PLIST"; then
  echo "Error: cannot read entitlements from provisioning profile '$PROFILE'." >&2
  echo "Make sure you pass a valid .mobileprovision file." >&2
  exit 1
fi
if [[ ! -s "$ENTITLEMENTS_PLIST" ]]; then
  echo "Error: extracted entitlements plist is empty. Check your provisioning profile." >&2
  exit 1
fi

# Make sure get-task-allow is removed or set to false to prevent launch issues with some side-loading methods.
PlistBuddy -c "Set :get-task-allow false" "$ENTITLEMENTS_PLIST" 2>/dev/null || PlistBuddy -c "Add :get-task-allow bool false" "$ENTITLEMENTS_PLIST" 2>/dev/null || true

echo "==> Entitlements extracted:"
PlistBuddy -c "Print" "$ENTITLEMENTS_PLIST" 2>/dev/null || true

echo "==> Installing provisioning profile"
cp "$PROFILE" "$APP/embedded.mobileprovision"

if [[ -n "$BUNDLE_ID" ]]; then
  echo "==> Rewriting bundle id -> $BUNDLE_ID"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Info.plist"
  for ext in "$APEX_DIR"/*.appex; do
    [[ -d "$ext" ]] || continue
    base="$BUNDLE_ID.$(basename "$ext" .appex)"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $base" "$ext/Info.plist"
  done
fi

echo "==> Fixing extended attributes"
xattr -cr "$APP" 2>/dev/null || true

echo "==> Re-signing frameworks / appex / app (using REAL entitlements)"
# 1) Sign nested frameworks first (deepest first).
find "$APP" -type d \( -name '*.framework' \) | while read -r item; do
  codesign --force --timestamp=none --sign "$IDENTITY" "$item"
done
# 2) Sign app extensions with the same entitlements.
if [ -d "$APEX_DIR" ]; then
    for ext in "$APEX_DIR"/*.appex; do
      [[ -d "$ext" ]] || continue
      codesign --force --timestamp=none --sign "$IDENTITY" --entitlements "$ENTITLEMENTS_PLIST" "$ext"
    done
fi
# 3) Sign the app itself with FULL entitlements from the provisioning profile.
codesign --force --timestamp=none --sign "$IDENTITY" --entitlements "$ENTITLEMENTS_PLIST" "$APP"

echo "==> Verifying signature"
codesign --verify --strict --verbose=2 "$APP"
if [ -d "$APEX_DIR" ]; then
    for ext in "$APEX_DIR"/*.appex; do
      codesign --verify --strict --verbose=1 "$ext" 2>&1 || true
    done
fi
echo ""
echo "==> Signed entitlements:"
codesign -d --entitlements - "$APP" 2>&1 || true

OUT="${IPA%.ipa}-signed.ipa"
echo "==> Zipping signed IPA -> $OUT"
( cd "$WORK" && zip -q -r -y "$OUT" Payload )
if [[ -f "$WORK/$OUT" ]]; then
  mv "$WORK/$OUT" "$(dirname "$IPA")/$OUT"
else
  ( cd "$WORK" && zip -q -r -y "$(dirname "$IPA")/$OUT" Payload )
fi

echo "==> Signed IPA ready: $(dirname "$IPA")/$OUT"
echo "    Install with Sideloadly / AltStore / Apple Configurator (free Apple ID works)."

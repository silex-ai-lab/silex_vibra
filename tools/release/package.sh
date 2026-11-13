#!/usr/bin/env bash
# Build, package and check a Vibra DMG. The CI dry run and a tag release run
# this same script; --release additionally signs with Developer ID, notarizes
# and staples.
# Usage: tools/release/package.sh --dry-run | --release
set -euo pipefail

mode=
case "${1:-}" in
  --dry-run) mode=dry-run ;;
  --release) mode=release ;;
  *)
    echo "usage: $(basename "$0") --dry-run | --release" >&2
    exit 2
    ;;
esac

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo"

die() { echo "error: $*" >&2; exit 1; }
note() { echo "== $*"; }

require_env() {
  local name
  for name in "$@"; do
    [ -n "${!name:-}" ] || die "$name is not set"
  done
}

version=$(sed -n 's/^VERSION[[:space:]]*:=[[:space:]]*//p' Makefile | head -n 1)
[ -n "$version" ] || die "could not read VERSION from the Makefile"
dmg="$repo/build/Vibra-$version.dmg"
bundle="$repo/build/Vibra.app"

if [ "$mode" = release ]; then
  require_env MACOS_SIGN_IDENTITY APPLE_TEAM_ID NOTARY_KEY_ID NOTARY_ISSUER_ID NOTARY_KEY_PATH
  [ -f "$NOTARY_KEY_PATH" ] || die "NOTARY_KEY_PATH does not name a file"
  sign_identity=$MACOS_SIGN_IDENTITY
  notary_args=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
  sign_identity=
  notary_args=()
fi

mount_dir=$(mktemp -d "${TMPDIR:-/tmp}/vibra-dmg.XXXXXX")
mounted=0

detach_dmg() {
  if [ "$mounted" -eq 1 ]; then
    hdiutil detach "$mount_dir" -force >/dev/null 2>&1 || true
    mounted=0
  fi
}

cleanup() {
  detach_dmg
  rm -rf "$mount_dir"
}
trap cleanup EXIT

attach_dmg() {
  hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$1" >/dev/null ||
    die "could not mount $1 read-only"
  mounted=1
}

check_mounted_app() {
  local app="$mount_dir/Vibra.app"
  local bin="$app/Contents/MacOS/Vibra"
  local archs sig cdhash team

  [ -d "$app" ] || die "there is no Vibra.app at the root of the DMG"
  [ -x "$bin" ] || die "Vibra.app in the DMG has no executable"

  archs=$(lipo -archs "$bin")
  echo "   lipo -archs: $archs"
  case " $archs " in
    *" arm64 "*) ;;
    *) die "the DMG's binary has no arm64 slice: $archs" ;;
  esac
  case " $archs " in
    *" x86_64 "*) ;;
    *) die "the DMG's binary has no x86_64 slice: $archs" ;;
  esac

  sig=$(codesign -d --verbose=4 "$app" 2>&1)
  cdhash=$(printf '%s\n' "$sig" | sed -n 's/^CDHash=//p')
  printf '%s\n' "$sig" | grep -q 'flags=.*runtime' ||
    die "the DMG's app is not signed with the hardened runtime"
  echo "   hardened runtime: yes"

  [ "$cdhash" = "$bundle_cdhash" ] ||
    die "the DMG's app has CDHash '${cdhash}', the built bundle has '${bundle_cdhash}'"
  echo "   CDHash matches the built bundle"

  if [ -f packaging/Vibra.entitlements ]; then
    codesign -d --entitlements :- "$app" 2>/dev/null |
      grep -q 'com.apple.security.automation.apple-events' ||
      die "the DMG's app is missing com.apple.security.automation.apple-events"
    echo "   automation entitlement: present"
  fi

  if [ "$mode" = release ]; then
    team=$(printf '%s\n' "$sig" | sed -n 's/^TeamIdentifier=//p')
    [ "$team" = "$APPLE_TEAM_ID" ] ||
      die "the DMG's app has TeamIdentifier '${team}', not APPLE_TEAM_ID"
    echo "   TeamIdentifier matches APPLE_TEAM_ID"
  fi
}

note "step 1: build universal, hardened, for $mode"
make app ARCHS="arm64 x86_64" HARDENED=1 SIGN_IDENTITY="$sign_identity"

note "step 2: verify the bundle and write the DMG"
codesign --verify --strict --verbose=2 "$bundle"
bundle_cdhash=$(codesign -d --verbose=4 "$bundle" 2>&1 | sed -n 's/^CDHash=//p')
[ -n "$bundle_cdhash" ] || die "could not read the built bundle's CDHash"
make dmg SIGN_IDENTITY="$sign_identity"
[ -f "$dmg" ] || die "make dmg did not write $dmg"

note "step 3: check the app inside the mounted DMG"
attach_dmg "$dmg"
check_mounted_app

if [ "$mode" = release ]; then
  note "step 4: notarize and staple"
  submit_out=$(xcrun notarytool submit "$dmg" "${notary_args[@]}" --wait --timeout 30m 2>&1) || {
    printf '%s\n' "$submit_out"
    die "notarytool submit failed"
  }
  printf '%s\n' "$submit_out"
  submission=$(printf '%s\n' "$submit_out" | sed -n 's/^ *id: //p' | head -n 1)
  status=$(printf '%s\n' "$submit_out" | sed -n 's/^ *status: //p' | head -n 1)
  if [ "$status" != "Accepted" ]; then
    echo "error: notarization status is '${status:-unknown}', not Accepted" >&2
    if [ -n "$submission" ]; then
      xcrun notarytool log "$submission" "${notary_args[@]}" || true
    fi
    exit 1
  fi
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"

  detach_dmg
  attach_dmg "$dmg"
  spctl_out=$(xcrun spctl -a -t open --context context:primary-signature -vv "$dmg" 2>&1) || {
    printf '%s\n' "$spctl_out"
    die "spctl rejected the DMG"
  }
  printf '%s\n' "$spctl_out"
  printf '%s\n' "$spctl_out" | grep -q 'source=Notarized Developer ID' ||
    die "the DMG is not reported as Notarized Developer ID"
  spctl_out=$(xcrun spctl -a -vv "$mount_dir/Vibra.app" 2>&1) || {
    printf '%s\n' "$spctl_out"
    die "spctl rejected the app inside the DMG"
  }
  printf '%s\n' "$spctl_out"
  printf '%s\n' "$spctl_out" | grep -q 'source=Notarized Developer ID' ||
    die "the app inside the DMG is not reported as Notarized Developer ID"
else
  note "step 5: launch the app inside the mounted DMG for 20 s"
  "$mount_dir/Vibra.app/Contents/MacOS/Vibra" &
  pid=$!
  sleep 20
  if kill -0 "$pid" 2>/dev/null; then
    echo "   still running after 20 s"
    kill "$pid"
    wait "$pid" 2>/dev/null || true
  else
    status=0
    wait "$pid" || status=$?
    die "the app inside the DMG exited with status $status before 20 s"
  fi
fi

note "step 6: write the SHA-256 of the final DMG"
dmg_name=$(basename "$dmg")
( cd "$repo/build" && shasum -a 256 "$dmg_name" >"$dmg_name.sha256" )
cat "$repo/build/$dmg_name.sha256"

note "done: $dmg"

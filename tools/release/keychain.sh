#!/usr/bin/env bash
# Put the release signing identity into a throwaway keychain that codesign
# will search, and take it out again.
# Usage: tools/release/keychain.sh setup <p12-path> <identity> <valid|any>
#        tools/release/keychain.sh teardown
#
# "valid" passes -v to security find-identity, which lists only identities
# whose certificate chain verifies. The dry run uses "any": its throwaway
# certificate is self-signed and no chain anchors it.
# Passwords come from MACOS_CERT_PASSWORD and MACOS_KEYCHAIN_PASSWORD, so this
# script's own argv stays clean. `security` still receives them as -p/-P
# arguments, which is acceptable on a single-tenant runner.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

[ -n "${RUNNER_TEMP:-}" ] || die "RUNNER_TEMP is not set"

keychain="$RUNNER_TEMP/release.keychain-db"
search_list_file="$RUNNER_TEMP/release-keychain-search-list.txt"
saved_keychains=()

# Save the search list that was there before, so teardown can put it back
# exactly. Replacing it instead of extending it makes the runner's login
# keychain invisible for the rest of the job.
read_search_list() {
  local line
  saved_keychains=()
  [ -f "$search_list_file" ] || return 0
  while IFS= read -r line; do
    if [ -n "$line" ]; then
      saved_keychains+=("$line")
    fi
  done <"$search_list_file"
}

save_search_list() {
  security list-keychains -d user |
    sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//' >"$search_list_file"
}

setup() {
  local p12=${1:-} identity=${2:-} validity=${3:-}

  if [ -z "$p12" ] || [ -z "$identity" ] || [ -z "$validity" ]; then
    die "usage: $(basename "$0") setup <p12-path> <identity> <valid|any>"
  fi
  [ -f "$p12" ] || die "$p12 does not name a file"
  case "$validity" in
    valid | any) ;;
    *) die "the third argument must be \"valid\" or \"any\", not \"$validity\"" ;;
  esac

  local name
  for name in MACOS_CERT_PASSWORD MACOS_KEYCHAIN_PASSWORD; do
    [ -n "${!name:-}" ] || die "$name is not set"
  done

  save_search_list

  # A leftover keychain from an earlier setup in the same $RUNNER_TEMP would
  # make create-keychain fail.
  security delete-keychain "$keychain" 2>/dev/null || true
  security create-keychain -p "$MACOS_KEYCHAIN_PASSWORD" "$keychain"
  security set-keychain-settings -lut 21600 "$keychain"
  security unlock-keychain -p "$MACOS_KEYCHAIN_PASSWORD" "$keychain"
  security import "$p12" -k "$keychain" -P "$MACOS_CERT_PASSWORD" -T /usr/bin/codesign
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "$MACOS_KEYCHAIN_PASSWORD" "$keychain" >/dev/null

  # The new keychain goes first so codesign finds the identity there; the
  # original entries follow unchanged.
  read_search_list
  if [ "${#saved_keychains[@]}" -gt 0 ]; then
    security list-keychains -d user -s "$keychain" "${saved_keychains[@]}"
  else
    security list-keychains -d user -s "$keychain"
  fi

  local find_args=(-p codesigning)
  if [ "$validity" = valid ]; then
    find_args=(-v -p codesigning)
  fi
  if ! security find-identity "${find_args[@]}" "$keychain" | grep -qF -- "$identity"; then
    die "security find-identity -p codesigning does not list \"$identity\" in $keychain"
  fi
  echo "keychain ready: $keychain lists \"$identity\""
}

# Succeeds even when setup never ran or failed half way: every step here is
# best effort, so the always() CI step cannot turn a signing failure into a
# messier one.
teardown() {
  read_search_list
  if [ "${#saved_keychains[@]}" -gt 0 ]; then
    security list-keychains -d user -s "${saved_keychains[@]}" || true
  fi
  security delete-keychain "$keychain" 2>/dev/null || true
  rm -f "$search_list_file"
  echo "keychain removed: $keychain"
}

case "${1:-}" in
  setup)
    shift
    setup "$@"
    ;;
  teardown)
    teardown
    ;;
  *)
    die "usage: $(basename "$0") setup <p12-path> <identity> <valid|any> | teardown"
    ;;
esac

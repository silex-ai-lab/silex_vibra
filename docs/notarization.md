# Notarize a Vibra release

Produce a prebuilt, Developer ID signed and stapled app ZIP. Run this workflow on macOS with Python 3 and Apple Command Line Tools. It does not publish, install, or replace an app.

## Prepare the signing machine

Use an existing, valid **Developer ID Application** identity with its private key in the local keychain. Use an already configured `notarytool` keychain profile for the same Apple Developer team.

The workflow accepts only the signing identity name or fingerprint and the profile name. Do not pass passwords, API keys, certificates, or private keys. It does not create or import credentials. If macOS asks to authorize private-key use, complete that prompt yourself.

Inspect the available identities without exporting keys:

```sh
security find-identity -v -p codesigning
```

Ad-hoc signatures and local development certificates cannot produce a notarized release. If no valid Developer ID Application identity exists, stop here.

Run the local preflight:

```sh
python3 tools/release/notarize.py \
  --identity 'Developer ID Application: Your Team (TEAMID1234)' \
  --profile 'your-existing-profile' \
  --check
```

This checks the local tools and identity. It does not create release files, build, use the private key, authenticate with Apple, or confirm that the profile works.

## Produce the release ZIP

Start with the intended release checkout. The script reads `VERSION` from `Makefile`. It requires the app's bundle ID, executable, and both version fields to match. For the published v0.3.0 source, use commit `9ad00e66ef9546d1ea03d5907ce083b654ce5911` as the source base.

Choose a new output directory that you can preserve until the submission finishes:

```sh
python3 tools/release/notarize.py \
  --identity 'Developer ID Application: Your Team (TEAMID1234)' \
  --profile 'your-existing-profile' \
  --output dist/notarization/0.3.0-arm64
```

The default output is `dist/notarization`. Keep it outside `build` because `make clean` deletes `build`. A fresh run refuses to overwrite an existing directory.

By default, the script runs `make app CONFIG=release SIGN_IDENTITY=`. To use an app you already built, add `--app /absolute/path/to/Vibra.app`. The script copies that app and never changes the supplied original. It supports the current single-executable app shape and rejects extra executables, nested code bundles, and symlinks. Build and notarize each architecture separately, or provide a valid universal app.

The script performs these steps:

1. Copy the app and include the repository's `LICENSE` and `NOTICE` in `Contents/Resources`.
2. Sign with Developer ID, hardened runtime, a secure timestamp, and `com.apple.security.automation.apple-events=true`. Preserve the app's existing Apple Events purpose string.
3. Verify the signature, signing team, timestamp, hardened runtime, and entitlements. Refuse `get-task-allow=true`.
4. Create `upload.zip`, record its SHA-256, and save a submission-attempt marker before contacting Apple.
5. Submit without waiting, save the UUID, and wait separately for up to 30 minutes.
6. Require Apple's `Accepted` status and a notarization log whose UUID and SHA-256 match the saved upload.
7. Extract the exact upload, staple the ticket, and verify the signature, staple, and Gatekeeper assessment.
8. Create the distribution ZIP, extract it again, repeat those checks, and print its SHA-256.

A successful arm64 run produces `Vibra-0.3.0-macos-arm64.zip` and `SHA256SUMS`. Intel uses `x86_64`. A universal app uses `universal`. The state reaches `complete` only after the final extracted app passes every check.

Distribute only the versioned ZIP from a completed run. Preserve the workspace for its receipt and logs. Do not distribute `upload.zip`, which contains the pre-staple app. No failed or unaccepted run reports a notarized distribution.

## Resume a known submission

After a wait timeout, interruption, or network error, keep the original directory and run:

```sh
python3 tools/release/notarize.py \
  --profile 'your-existing-profile' \
  --output dist/notarization/0.3.0-arm64 \
  --resume
```

Do not pass `--identity` or `--app` during resume. The script uses the saved signer and original upload. It does not rebuild, re-sign, or upload a second time. It rechecks Apple's status and log before stapling a fresh extraction.

A submission still marked `prepared` has not attempted an upload. Resuming that state starts its first submission. A submission marked `submitting` may already exist at Apple and requires reconciliation below.

If Apple rejects the app, inspect `notary-log.json`, fix the reported issue, and start a new run in a new directory. Never replace a rejected run's upload archive.

## Recover an uncertain upload

If upload fails before a UUID is saved, the script stops. It never assumes that Apple received nothing.

Inspect the preserved `submit.stdout.json` and `submit.stderr.txt`. If they do not identify the submission, inspect Apple's history with the same profile:

```sh
xcrun notarytool history \
  --keychain-profile 'your-existing-profile' \
  --output-format json
```

Select the submission for that attempt, then supply its UUID:

```sh
python3 tools/release/notarize.py \
  --profile 'your-existing-profile' \
  --output dist/notarization/0.3.0-arm64 \
  --resume \
  --submission-id 'APPLE-SUBMISSION-UUID'
```

The UUID is not enough to authorize stapling. The completed Apple log must also match the preserved upload's SHA-256. The script saves a recovered UUID only after that match. If the selected UUID is still in progress, repeat the same recovery command later. If the log does not match, investigate and supply the correct UUID without changing the workspace. Do not automatically start another upload when the prior outcome remains unknown.

One process owns each workspace through an OS file lock. A crashed process releases that lock. Temporary directories have `.sign-` or `.staple-` prefixes. Remove abandoned temporary directories only after confirming no release process uses the workspace.

## Verify the workflow without credentials

Run the standard-library tests:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -B tools/release/test_notarize.py
```

These tests simulate signing, Apple responses, stapling, and Gatekeeper. They exercise missing identities, rejected submissions, timeout recovery, uncertain uploads, mismatched logs, changed archives, entitlement checks, and final ZIP extraction. They do not prove real signing, Apple acceptance, stapling, or Gatekeeper behavior.

Test the real app separately with `make app` and `make test SWIFT_BUILD_SYSTEM=native`. Those commands produce and test the developer build. They do not notarize it.

A Homebrew formula that builds from source still creates a new local signature. It does not inherit notarization from this prebuilt ZIP. A future binary distribution must install the verified prebuilt artifact to retain its signed and stapled contents.

## Apple references

- [Notarize macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
- [Apple Events automation entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events).
- Run `xcrun notarytool help submit`, `xcrun notarytool help wait`, and `xcrun notarytool help log` for the installed tool's options.

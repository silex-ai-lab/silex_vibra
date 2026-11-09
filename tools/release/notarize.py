#!/usr/bin/env python3
"""Sign, notarize, staple, and verify a versioned Vibra app ZIP on macOS."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]
ENTITLEMENTS = Path(__file__).with_name("Vibra.entitlements")
PHASES = {"prepared", "submitting", "submitted", "accepted", "complete"}


class ReleaseError(Exception):
    pass


def run(*args, check=True):
    result = subprocess.run([str(arg) for arg in args], capture_output=True, text=True)
    if check and result.returncode:
        raise ReleaseError(f"Command failed: {' '.join(map(str, args))}\n{result.stdout}{result.stderr}")
    return result


def json_output(result):
    try:
        value = json.loads(result.stdout)
        if not isinstance(value, dict):
            raise ValueError("expected a JSON object")
        return value
    except (ValueError, TypeError) as error:
        raise ReleaseError(f"Apple returned no valid JSON. See saved response. {error}") from error


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def save(output, state):
    temporary = output / "state.json.tmp"
    with temporary.open("w") as target:
        json.dump(state, target, indent=2, sort_keys=True)
        target.write("\n")
        target.flush()
        os.fsync(target.fileno())
    temporary.replace(output / "state.json")
    directory = os.open(output, os.O_RDONLY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def submission_id(value):
    try:
        return str(uuid.UUID(value))
    except (ValueError, TypeError, AttributeError) as error:
        raise ReleaseError("The submission ID must be an Apple submission UUID.") from error


def preflight(identity=None):
    if sys.platform != "darwin":
        raise ReleaseError("This workflow requires macOS.")
    for tool in ("notarytool", "stapler"):
        run("/usr/bin/xcrun", "--find", tool)
    if not identity:
        return None
    identities = run("/usr/bin/security", "find-identity", "-v", "-p", "codesigning").stdout
    matches = re.findall(r'\b([A-Fa-f0-9]{40}) "(Developer ID Application: [^"\n]+)"', identities)
    matches = [(fingerprint.upper(), name) for fingerprint, name in matches
               if identity == name or identity.upper() == fingerprint.upper()]
    if len(matches) != 1:
        raise ReleaseError("Select exactly one valid Developer ID Application identity by full name or SHA-1. "
                           "Ad-hoc and local signing certificates cannot be notarized.")
    fingerprint, name = matches[0]
    team = re.search(r"\(([A-Z0-9]{10})\)$", name)
    if not team:
        raise ReleaseError("The Developer ID identity has no valid Team ID.")
    return {"fingerprint": fingerprint, "name": name, "team": team.group(1)}


def version():
    match = re.search(r"^VERSION\s*[:?]?=\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$",
                      (ROOT / "Makefile").read_text(), re.MULTILINE)
    if not match:
        raise ReleaseError("Makefile must declare one release VERSION.")
    return match.group(1)


def bundle_info(app, expected_version):
    try:
        with (app / "Contents/Info.plist").open("rb") as source:
            info = plistlib.load(source)
    except (OSError, ValueError) as error:
        raise ReleaseError(f"Cannot read Vibra's Info.plist: {error}") from error
    expected = {"CFBundleIdentifier": "ai.silexlab.vibra", "CFBundleExecutable": "Vibra",
                "CFBundleShortVersionString": expected_version, "CFBundleVersion": expected_version}
    if any(info.get(key) != value for key, value in expected.items()):
        raise ReleaseError(f"Expected Vibra {expected_version} with bundle ID ai.silexlab.vibra.")
    if not info.get("NSAppleEventsUsageDescription", "").strip():
        raise ReleaseError("NSAppleEventsUsageDescription is required for terminal automation.")
    binary = app / "Contents/MacOS/Vibra"
    macho = {b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
             b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}
    for path in app.rglob("*"):
        if path.is_symlink() or path.suffix in {".app", ".framework", ".xpc", ".appex", ".bundle"}:
            raise ReleaseError(f"This workflow supports only Vibra's single-executable bundle. Unexpected code: {path}")
        if path.is_file() and path != binary:
            with path.open("rb") as source:
                magic = source.read(4)
            if path.stat().st_mode & 0o111 or magic in macho:
                raise ReleaseError(f"Unexpected executable in the app bundle: {path}")
    architectures = set(run("/usr/bin/lipo", "-archs", app / "Contents/MacOS/Vibra").stdout.split())
    if architectures == {"arm64", "x86_64"}:
        return "universal"
    if architectures in ({"arm64"}, {"x86_64"}):
        return next(iter(architectures))
    raise ReleaseError(f"Unsupported app architectures: {sorted(architectures)}")


def verify_signature(app, signer):
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", app)
    details = run("/usr/bin/codesign", "-d", "--verbose=4", app)
    text = details.stdout + details.stderr
    required = (f"Authority={signer['name']}\n", f"TeamIdentifier={signer['team']}\n", "Timestamp=")
    if "Signature=adhoc" in text or "Timestamp=none" in text or not all(value in text for value in required) or not re.search(r"flags=.*\bruntime\b", text):
        raise ReleaseError("The app must have the selected Developer ID signature, hardened runtime, and secure timestamp.")
    result = run("/usr/bin/codesign", "-d", "--entitlements", ":-", app)
    text = result.stdout + result.stderr
    try:
        entitlements = plistlib.loads(text[text.index("<?xml"):text.index("</plist>") + 8].encode())
    except (ValueError, plistlib.InvalidFileException) as error:
        raise ReleaseError("Cannot verify signed app entitlements.") from error
    if entitlements.get("com.apple.security.automation.apple-events") is not True:
        raise ReleaseError("The signed app must allow Apple Events automation.")
    if entitlements.get("com.apple.security.get-task-allow"):
        raise ReleaseError("Release signatures must not enable get-task-allow.")


def prepare(output, args, signer):
    release_version = version()
    if args.app:
        source = args.app.resolve()
    else:
        run("/usr/bin/make", "-C", ROOT, "app", "CONFIG=release", "SIGN_IDENTITY=")
        source = ROOT / "build/Vibra.app"
    with tempfile.TemporaryDirectory(prefix=".sign-", dir=output) as workspace:
        app = Path(workspace) / "Vibra.app"
        run("/usr/bin/ditto", source, app)
        architecture = bundle_info(app, release_version)
        resources = app / "Contents/Resources"
        resources.mkdir(exist_ok=True)
        for notice in ("LICENSE", "NOTICE"):
            shutil.copyfile(ROOT / notice, resources / notice)
        run("/usr/bin/codesign", "--force", "--options", "runtime", "--timestamp",
            "--entitlements", ENTITLEMENTS, "--sign", signer["fingerprint"], app)
        verify_signature(app, signer)
        run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, output / "upload.zip")
    state = {"schema": 1, "phase": "prepared", "version": release_version, "arch": architecture, "signer": signer,
             "profile": args.profile, "upload_sha256": sha256(output / "upload.zip"), "submission_id": None}
    save(output, state)
    return state


def load(output, profile):
    try:
        state = json.loads((output / "state.json").read_text())
        valid = (state["schema"] == 1 and state["phase"] in PHASES and state["profile"] == profile
                 and re.fullmatch(r"[0-9a-f]{64}", state["upload_sha256"])
                 and state["arch"] in {"arm64", "x86_64", "universal"}
                 and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", state["version"])
                 and state["signer"]["name"].startswith("Developer ID Application: ")
                 and re.fullmatch(r"[A-Z0-9]{10}", state["signer"]["team"]))
        if not valid:
            raise ValueError("Invalid release state")
        if state["phase"] in {"prepared", "submitting"} and state["submission_id"] is not None:
            raise ValueError("Unexpected submission UUID before a confirmed submission")
        if state["submission_id"] is not None:
            state["submission_id"] = submission_id(state["submission_id"])
        elif state["phase"] in {"submitted", "accepted", "complete"}:
            raise ValueError("Missing submission UUID")
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        raise ReleaseError("Cannot resume this state with this keychain profile. Keep the workspace for diagnosis.") from error
    if sha256(output / "upload.zip") != state["upload_sha256"]:
        raise ReleaseError("The upload ZIP changed. Do not submit, staple, or distribute this workspace.")
    return state


def notarize(output, state, recovery_id=None):
    profile = state["profile"]
    if recovery_id:
        recovered = submission_id(recovery_id)
        if state["submission_id"] and state["submission_id"] != recovered:
            raise ReleaseError("The recovery UUID differs from the saved submission UUID.")
        if state["phase"] == "prepared":
            raise ReleaseError("No submission attempt needs recovery. Resume without --submission-id.")
    if state["phase"] == "prepared":
        state["phase"] = "submitting"
        save(output, state)
        result = run("/usr/bin/xcrun", "notarytool", "submit", output / "upload.zip", "--no-wait",
                     "--keychain-profile", profile, "--output-format", "json", check=False)
        (output / "submit.stdout.json").write_text(result.stdout)
        (output / "submit.stderr.txt").write_text(result.stderr)
        try:
            identifier = submission_id(json_output(result).get("id"))
        except ReleaseError as error:
            raise ReleaseError("Submission outcome is uncertain. Do not submit again. Inspect notarytool history, "
                               "then resume this workspace with --submission-id UUID.") from error
        state.update(phase="submitted", submission_id=identifier)
        save(output, state)
    if state["phase"] == "submitting" and not recovery_id:
        raise ReleaseError("A prior submission may have reached Apple. Do not submit again. Inspect notarytool history, "
                           "then resume with --submission-id UUID.")
    identifier = state["submission_id"] or recovered
    print(f"Apple submission {identifier}")
    result = run("/usr/bin/xcrun", "notarytool", "info", identifier, "--keychain-profile", profile,
                 "--output-format", "json")
    info = json_output(result)
    if info.get("status") == "In Progress":
        result = run("/usr/bin/xcrun", "notarytool", "wait", identifier, "--keychain-profile", profile,
                     "--timeout", "30m", "--output-format", "json", check=False)
        (output / "wait.stdout.json").write_text(result.stdout)
        (output / "wait.stderr.txt").write_text(result.stderr)
        info = json_output(run("/usr/bin/xcrun", "notarytool", "info", identifier,
                               "--keychain-profile", profile, "--output-format", "json"))
    (output / "info.json").write_text(json.dumps(info, indent=2) + "\n")
    if submission_id(info.get("id")) != identifier:
        raise ReleaseError("Apple's response identifies a different submission.")
    status = info.get("status")
    if status in {"Accepted", "Invalid", "Rejected"}:
        run("/usr/bin/xcrun", "notarytool", "log", identifier, "--keychain-profile", profile, output / "notary-log.json")
        try:
            log = json.loads((output / "notary-log.json").read_text())
            bound = (submission_id(log.get("jobId")) == identifier and log.get("status") == status
                     and log.get("sha256", "").lower() == state["upload_sha256"])
        except (OSError, ValueError, TypeError, AttributeError) as error:
            raise ReleaseError("Cannot verify Apple's notarization log.") from error
        if not bound:
            raise ReleaseError("Apple's completed log does not match this submission and upload ZIP SHA-256.")
        state.update(phase="submitted", submission_id=identifier)
        save(output, state)
    if status != "Accepted":
        raise ReleaseError(f"Apple status is {status!r}, not Accepted. No distribution ZIP was produced. "
                           "For In Progress or a network error, resume this workspace. Inspect notary-log.json after rejection.")
    state["phase"] = "accepted"
    save(output, state)


def assess(app, state):
    for notice in ("LICENSE", "NOTICE"):
        if not (app / "Contents/Resources" / notice).is_file():
            raise ReleaseError(f"The distribution app is missing {notice}.")
    if bundle_info(app, state["version"]) != state["arch"]:
        raise ReleaseError("The distribution app architecture changed.")
    verify_signature(app, state["signer"])
    run("/usr/bin/xcrun", "stapler", "validate", app)
    result = run("/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=2", app)
    if "source=Notarized Developer ID" not in result.stdout + result.stderr:
        raise ReleaseError("Gatekeeper did not identify a Notarized Developer ID app.")


def finish(output, state):
    with tempfile.TemporaryDirectory(prefix=".staple-", dir=output) as workspace:
        workspace = Path(workspace)
        app = workspace / "Vibra.app"
        run("/usr/bin/ditto", "-x", "-k", output / "upload.zip", workspace)
        run("/usr/bin/xcrun", "stapler", "staple", app)
        assess(app, state)
        archive = workspace / "distribution.zip"
        run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive)
        extracted = workspace / "roundtrip"
        run("/usr/bin/ditto", "-x", "-k", archive, extracted)
        assess(extracted / "Vibra.app", state)
        filename = f"Vibra-{state['version']}-macos-{state['arch']}.zip"
        archive.replace(output / filename)
    state.update(phase="complete", distribution=filename, distribution_sha256=sha256(output / filename))
    save(output, state)
    (output / "SHA256SUMS").write_text(f"{state['distribution_sha256']}  {filename}\n")
    print(f"Verified notarized distribution: {output / filename}")
    print(f"SHA-256: {state['distribution_sha256']}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", help="Full Developer ID Application name or SHA-1. Never a password or private key.")
    parser.add_argument("--profile", required=True, help="Existing notarytool keychain profile name.")
    parser.add_argument("--app", type=Path, help="Copy an existing Vibra.app instead of running make app.")
    parser.add_argument("--output", type=Path, default=ROOT / "dist/notarization", help="New workspace, or the original workspace for --resume.")
    parser.add_argument("--check", action="store_true", help="Local tools and identity checks only. No build, release files, or Apple contact.")
    parser.add_argument("--resume", action="store_true", help="Continue the saved submission. Never submit a second time.")
    parser.add_argument("--submission-id", help="Recover an uncertain upload using its Apple UUID. Requires --resume.")
    args = parser.parse_args(argv)
    if not args.profile.strip() or args.profile.startswith("-"):
        parser.error("--profile must be an existing keychain profile name")
    if args.resume and (args.app or args.identity or args.check):
        parser.error("--resume uses the saved app and signer. Omit --app, --identity, and --check")
    if args.submission_id and not args.resume:
        parser.error("--submission-id requires --resume")
    if not args.resume and not args.identity:
        parser.error("--identity is required for a new run or --check")
    signer = preflight(args.identity)
    if args.check:
        print("Local preflight passed. Apple credentials, signing, and notarization have not been tested.")
        return
    output = args.output.resolve()
    if not args.resume:
        output.mkdir(parents=True, exist_ok=False, mode=0o700)
    with (output / ".lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ReleaseError("Another release process owns this workspace.") from error
        state = load(output, args.profile) if args.resume else prepare(output, args, signer)
        notarize(output, state, args.submission_id)
        finish(output, state)


if __name__ == "__main__":
    try:
        main()
    except (ReleaseError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)

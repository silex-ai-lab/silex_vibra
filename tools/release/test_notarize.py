#!/usr/bin/env python3
"""Credential-free workflow tests. Apple and signature commands are simulated."""

import importlib.util
import fcntl
import io
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SPEC = importlib.util.spec_from_file_location("notarize", Path(__file__).with_name("notarize.py"))
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)
IDENTITY = "Developer ID Application: Example Team (ABCDE12345)"
FINGERPRINT = "A" * 40
UUID = "12345678-1234-1234-1234-123456789abc"
OTHER_UUID = "87654321-4321-4321-4321-abcdef123456"
PROFILE = "existing-test-profile"
SIGNER = {"name": IDENTITY, "team": "ABCDE12345", "fingerprint": FINGERPRINT}


class FakeTools:
    def __init__(self, output):
        self.output = output
        self.calls = []
        self.status = "Accepted"
        self.submit_output = json.dumps({"id": UUID})
        self.submit_code = 0
        self.log_hash = None
        self.log_id = None
        self.identities = f'  1) {FINGERPRINT} "{IDENTITY}"\n     1 valid identities found\n'
        self.signature = f"Authority={IDENTITY}\nTeamIdentifier=ABCDE12345\nTimestamp=Nov 7, 2026\nCodeDirectory flags=0x10000(runtime)\n"
        self.entitlements = {"com.apple.security.automation.apple-events": True}
        self.gatekeeper = "source=Notarized Developer ID\n"
        self.wait_accepts = True

    def __call__(self, *args, check=True):
        args = [str(arg) for arg in args]
        self.calls.append(args)
        stdout, stderr, code = "", "", 0
        if args[0] == "/usr/bin/security":
            stdout = self.identities
        elif args[0] == "/usr/bin/lipo":
            stdout = "arm64\n"
        elif args[0] == "/usr/bin/codesign":
            if "--entitlements" in args and "-d" in args:
                stdout = plistlib.dumps(self.entitlements).decode()
            elif "-d" in args:
                stderr = self.signature
        elif args[0] == "/usr/sbin/spctl":
            stderr = self.gatekeeper
        elif args[0] == "/usr/bin/ditto":
            if "-c" in args:
                app, destination = Path(args[-2]), Path(args[-1])
                with zipfile.ZipFile(destination, "w") as archive:
                    for file in app.rglob("*"):
                        if file.is_file():
                            archive.write(file, file.relative_to(app.parent))
            elif "-x" in args:
                with zipfile.ZipFile(args[-2]) as archive:
                    archive.extractall(args[-1])
            else:
                shutil.copytree(args[-2], args[-1])
        elif args[:3] == ["/usr/bin/xcrun", "--find", "notarytool"] or args[:3] == ["/usr/bin/xcrun", "--find", "stapler"]:
            stdout = "/usr/bin/fake-tool\n"
        elif args[:2] == ["/usr/bin/xcrun", "notarytool"]:
            operation = args[2]
            if operation == "submit":
                stdout, code = self.submit_output, self.submit_code
            elif operation == "info":
                stdout = json.dumps({"id": args[3], "status": self.status})
            elif operation == "wait":
                if self.wait_accepts:
                    self.status = "Accepted"
                else:
                    code, stderr = 1, "Timed out. Submission remains in progress."
                stdout = json.dumps({"id": args[3], "status": self.status})
            elif operation == "log":
                log = {"jobId": self.log_id or args[3], "status": self.status,
                       "sha256": self.log_hash or release.sha256(self.output / "upload.zip")}
                Path(args[-1]).write_text(json.dumps(log))
            else:
                raise AssertionError(args)
        elif args[:2] == ["/usr/bin/xcrun", "stapler"]:
            app = Path(args[-1])
            ticket = app / "Contents/ticket"
            if args[2] == "staple":
                ticket.write_text("simulated Apple ticket")
            elif args[2] == "validate" and not ticket.exists():
                code, stderr = 1, "No ticket"
        else:
            raise AssertionError(f"Unexpected command: {args}")
        result = subprocess.CompletedProcess(args, code, stdout, stderr)
        if code and check:
            raise release.ReleaseError(stderr)
        return result

    def count(self, operation):
        return sum(call[:3] == ["/usr/bin/xcrun", "notarytool", operation] for call in self.calls)


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.output = self.root / "release"
        self.app = self.root / "Vibra.app"
        (self.app / "Contents/MacOS").mkdir(parents=True)
        (self.app / "Contents/MacOS/Vibra").write_bytes(b"simulated arm64 executable")
        self.info = {"CFBundleIdentifier": "ai.silexlab.vibra", "CFBundleExecutable": "Vibra",
                     "CFBundleShortVersionString": "0.3.0", "CFBundleVersion": "0.3.0",
                     "NSAppleEventsUsageDescription": "Focus a terminal session."}
        self.write_info()
        self.tools = FakeTools(self.output)
        self.addCleanup(patch.stopall)
        patch.object(release, "run", self.tools).start()
        patch("sys.stdout", new_callable=io.StringIO).start()
        patch.object(release.sys, "platform", "darwin").start()

    def write_info(self):
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(self.info))

    def start(self):
        release.main(["--profile", PROFILE, "--identity", IDENTITY, "--app", str(self.app), "--output", str(self.output)])

    def resume(self, identifier=None):
        args = ["--profile", PROFILE, "--resume", "--output", str(self.output)]
        if identifier:
            args += ["--submission-id", identifier]
        release.main(args)

    def state(self):
        return json.loads((self.output / "state.json").read_text())

    def test_complete_zip_contains_stapled_app_and_matches_checksum(self):
        self.start()
        state = self.state()
        self.assertEqual(state["phase"], "complete")
        archive = self.output / "Vibra-0.3.0-macos-arm64.zip"
        self.assertEqual(state["distribution_sha256"], release.sha256(archive))
        with zipfile.ZipFile(archive) as distribution:
            self.assertIn("Vibra.app/Contents/ticket", distribution.namelist())
            self.assertEqual(distribution.read("Vibra.app/Contents/Resources/LICENSE"), (release.ROOT / "LICENSE").read_bytes())
            self.assertEqual(distribution.read("Vibra.app/Contents/Resources/NOTICE"), (release.ROOT / "NOTICE").read_bytes())
        with zipfile.ZipFile(self.output / "upload.zip") as upload:
            self.assertNotIn("Vibra.app/Contents/ticket", upload.namelist())
        self.assertFalse((self.app / "Contents/ticket").exists())
        signing = next(call for call in self.tools.calls if call[0] == "/usr/bin/codesign" and "--sign" in call)
        self.assertIn("--timestamp", signing)
        self.assertEqual(signing[signing.index("--options") + 1], "runtime")
        self.assertEqual(self.tools.count("submit"), 1)

    def test_missing_developer_id_fails_before_writes_or_apple(self):
        self.tools.identities = "0 valid identities found"
        with self.assertRaisesRegex(release.ReleaseError, "valid Developer ID"):
            self.start()
        self.assertFalse(self.output.exists())
        self.assertEqual(self.tools.count("submit"), 0)

    def test_local_identity_cannot_pass_preflight(self):
        self.tools.identities = f'1) {FINGERPRINT} "vibra local signing"'
        with self.assertRaises(release.ReleaseError):
            release.preflight("vibra local signing")

    def test_check_never_builds_writes_or_contacts_apple(self):
        release.main(["--profile", PROFILE, "--identity", IDENTITY, "--check", "--output", str(self.output)])
        self.assertFalse(self.output.exists())
        self.assertEqual(self.tools.count("submit"), 0)
        self.assertTrue(all(call[0] == "/usr/bin/security" or "--find" in call for call in self.tools.calls))

    def test_invalid_response_never_produces_distribution(self):
        self.tools.status = "Invalid"
        with self.assertRaisesRegex(release.ReleaseError, "not Accepted"):
            self.start()
        self.assertEqual(self.state()["phase"], "submitted")
        self.assertFalse(list(self.output.glob("Vibra-*.zip")))
        self.assertTrue((self.output / "notary-log.json").exists())

    def test_in_progress_timeout_keeps_uuid_for_safe_resume(self):
        self.tools.status, self.tools.wait_accepts = "In Progress", False
        with self.assertRaisesRegex(release.ReleaseError, "not Accepted"):
            self.start()
        self.assertEqual(self.state()["submission_id"], UUID)
        self.tools.status = "Accepted"
        self.resume()
        self.assertEqual(self.tools.count("submit"), 1)
        self.assertEqual(self.state()["phase"], "complete")

    def test_wait_can_finish_before_assessment(self):
        self.tools.status = "In Progress"
        self.start()
        self.assertEqual(self.tools.count("wait"), 1)
        self.assertEqual(self.state()["phase"], "complete")

    def test_unknown_submit_never_retries_automatically(self):
        self.tools.submit_output, self.tools.submit_code = "", 1
        with self.assertRaisesRegex(release.ReleaseError, "uncertain"):
            self.start()
        self.assertEqual(self.state()["phase"], "submitting")
        with self.assertRaisesRegex(release.ReleaseError, "may have reached Apple"):
            self.resume()
        self.assertEqual(self.tools.count("submit"), 1)
        self.resume(UUID)
        self.assertEqual(self.state()["phase"], "complete")
        self.assertEqual(self.tools.count("submit"), 1)

    def test_wrong_uncertain_recovery_id_does_not_poison_workspace(self):
        self.tools.submit_output = ""
        with self.assertRaises(release.ReleaseError):
            self.start()
        self.tools.log_hash = "0" * 64
        with self.assertRaisesRegex(release.ReleaseError, "does not match"):
            self.resume(OTHER_UUID)
        self.assertEqual(self.state()["phase"], "submitting")
        self.assertIsNone(self.state()["submission_id"])
        self.tools.log_hash = None
        self.resume(UUID)
        self.assertEqual(self.state()["submission_id"], UUID)
        self.assertEqual(self.state()["phase"], "complete")
        self.assertEqual(self.tools.count("submit"), 1)

    def test_os_lock_prevents_concurrent_workspace_owner(self):
        self.output.mkdir()
        with (self.output / ".lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(release.ReleaseError, "Another release process"):
                self.resume()
        self.assertEqual(self.tools.count("submit"), 0)

    def test_nonzero_submit_with_uuid_recovers_without_upload_retry(self):
        self.tools.submit_code = 1
        self.start()
        self.assertEqual(self.state()["phase"], "complete")
        self.assertEqual(self.tools.count("submit"), 1)

    def test_wrong_log_hash_blocks_stapling_and_distribution(self):
        self.tools.log_hash = "0" * 64
        with self.assertRaisesRegex(release.ReleaseError, "does not match"):
            self.start()
        self.assertFalse(any(call[:3] == ["/usr/bin/xcrun", "stapler", "staple"] for call in self.tools.calls))
        self.assertFalse(list(self.output.glob("Vibra-*.zip")))

    def test_wrong_log_uuid_blocks_distribution(self):
        self.tools.log_id = OTHER_UUID
        with self.assertRaisesRegex(release.ReleaseError, "does not match"):
            self.start()
        self.assertFalse(list(self.output.glob("Vibra-*.zip")))

    def test_changed_upload_blocks_resume_before_contacting_apple(self):
        self.tools.status = "Invalid"
        with self.assertRaises(release.ReleaseError):
            self.start()
        (self.output / "upload.zip").write_bytes(b"changed archive")
        calls = len(self.tools.calls)
        with self.assertRaisesRegex(release.ReleaseError, "upload ZIP changed"):
            self.resume()
        self.assertTrue(all("--find" in call for call in self.tools.calls[calls:]))

    def test_wrong_recovery_uuid_cannot_replace_known_uuid(self):
        self.tools.status = "Invalid"
        with self.assertRaises(release.ReleaseError):
            self.start()
        with self.assertRaisesRegex(release.ReleaseError, "differs"):
            self.resume(OTHER_UUID)
        self.assertEqual(self.state()["submission_id"], UUID)

    def test_complete_resume_never_resigns_or_resubmits(self):
        self.start()
        self.resume()
        self.assertEqual(self.tools.count("submit"), 1)
        self.assertEqual(sum("--sign" in call for call in self.tools.calls), 1)
        self.assertEqual(self.state()["phase"], "complete")

    def test_missing_runtime_timestamp_or_developer_id_is_rejected(self):
        for missing in ["Timestamp=Nov 7, 2026\n", "CodeDirectory flags=0x10000(runtime)\n", f"Authority={IDENTITY}\n"]:
            original = self.tools.signature
            self.tools.signature = original.replace(missing, "")
            with self.subTest(missing=missing), self.assertRaisesRegex(release.ReleaseError, "Developer ID signature"):
                release.verify_signature(self.app, SIGNER)
            self.tools.signature = original

    def test_apple_events_entitlement_and_no_debugger_are_required(self):
        for entitlements in [{}, {"com.apple.security.automation.apple-events": True, "com.apple.security.get-task-allow": True}]:
            self.tools.entitlements = entitlements
            with self.subTest(entitlements=entitlements), self.assertRaises(release.ReleaseError):
                release.verify_signature(self.app, SIGNER)

    def test_wrong_version_and_missing_purpose_stop_before_upload(self):
        for key, value in [("CFBundleShortVersionString", "9.9.9"), ("NSAppleEventsUsageDescription", "")]:
            original = self.info.copy()
            self.info[key] = value
            self.write_info()
            with self.subTest(key=key), self.assertRaises(release.ReleaseError):
                release.bundle_info(self.app, "0.3.0")
            self.info = original
        self.assertEqual(self.tools.count("submit"), 0)

    def test_non_notarized_gatekeeper_result_blocks_final_zip(self):
        self.tools.gatekeeper = "source=Developer ID\n"
        with self.assertRaisesRegex(release.ReleaseError, "Gatekeeper"):
            self.start()
        self.assertEqual(self.state()["phase"], "accepted")
        self.assertFalse(list(self.output.glob("Vibra-*.zip")))

    def test_unknown_executables_and_symlinks_are_rejected(self):
        unknown = self.app / "Contents/helper"
        unknown.write_bytes(b"\xcf\xfa\xed\xfeextra Mach-O")
        with self.assertRaisesRegex(release.ReleaseError, "Unexpected executable"):
            release.bundle_info(self.app, "0.3.0")
        unknown.unlink()
        unknown.symlink_to(self.app / "Contents/MacOS/Vibra")
        with self.assertRaisesRegex(release.ReleaseError, "single-executable"):
            release.bundle_info(self.app, "0.3.0")

    def test_invalid_resume_state_is_rejected_without_asserts(self):
        self.tools.status = "Invalid"
        with self.assertRaises(release.ReleaseError):
            self.start()
        state = self.state()
        state["phase"] = "imaginary"
        release.save(self.output, state)
        with self.assertRaisesRegex(release.ReleaseError, "Cannot resume"):
            self.resume()

    def test_preupload_states_reject_non_null_submission_ids_before_apple_contact(self):
        self.tools.status = "Invalid"
        with self.assertRaises(release.ReleaseError):
            self.start()
        state = self.state()
        for phase in ("prepared", "submitting"):
            for identifier in (UUID, "", 0):
                state.update(phase=phase, submission_id=identifier)
                release.save(self.output, state)
                call_count = len(self.tools.calls)
                with self.subTest(phase=phase, identifier=identifier), self.assertRaisesRegex(release.ReleaseError, "Cannot resume"):
                    self.resume()
                self.assertFalse(any(call[:2] == ["/usr/bin/xcrun", "notarytool"]
                                     for call in self.tools.calls[call_count:]))
        self.assertEqual(self.tools.count("submit"), 1)

    def test_invalid_apple_json_is_not_an_accepted_result(self):
        for value in ["not JSON", "[]", "null"]:
            with self.subTest(value=value), self.assertRaises(release.ReleaseError):
                release.json_output(subprocess.CompletedProcess([], 0, value, ""))

    def test_existing_workspace_is_never_overwritten_by_fresh_run(self):
        self.output.mkdir()
        sentinel = self.output / "sentinel"
        sentinel.write_text("keep")
        with self.assertRaises(FileExistsError):
            self.start()
        self.assertEqual(sentinel.read_text(), "keep")
        self.assertEqual(self.tools.count("submit"), 0)


if __name__ == "__main__":
    print("Credential-free tests. Apple, signing, and stapling commands are simulated.", flush=True)
    unittest.main(verbosity=2)

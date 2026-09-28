# Development

Building, testing and signing Vibra from source. The short install is in the
[README](../README.md#install).

## Test run

The fastest way to confirm it works, without touching the menu bar at all:

```sh
make probe
```

That runs every adapter once against your real session files and prints what it
found, then exits. Expect something like:

```
Claude Code: available=true sessions=2
  - my-project [working] ev=producing 35067076 tok $83.8576 model=claude-opus-5
  - other-repo [awaitingInput] ev=turnComplete 59601496 tok $125.9708 model=claude-opus-5
Codex: available=true sessions=1
  - my-project [stalled] ev=producing 567852 tok $0.4327 model=gpt-5.6-sol
OpenCode: available=true sessions=1
  - my-project [idle] ev=unknown 13365036 tok $0.4847 model=deepseek-v4-pro
Cursor: available=false sessions=0
VS Code: available=true sessions=1
  - my-project [blocked] ev=permissionPrompt 1840 tok n/a model=copilot/gpt-5 via=vscode
total sessions: 5
```

`probe` prints counts, project names and states. It never prints message
content. It exits `2` if it found no sessions at all, which usually means you
have not used any of the supported agents in the last 12 hours.

**To see it change live:** start a Claude Code or Codex session in another
terminal, give it a task, and run `make probe` again — that session should
appear as `working`. When it finishes and waits for you, it flips to
`awaitingInput` and the menu bar count shows `1!`. The same works for a
Copilot Chat in VS Code: send a message in Agent mode, and while it waits on
**Allow** for a terminal command, `make probe` shows it as `blocked`.

### Run the tests

```sh
make test
```

Expect `Test run with N tests in M suites passed` followed by
`OK: tests executed, canary present`.

### Development loop

```sh
make restart    # rebuild and relaunch the running copy
make probe      # check adapter output without the UI

# check whether macOS will actually deliver notifications here
/Applications/Vibra.app/Contents/MacOS/Vibra --test-notification
```

### Stable signing for development

`make install` ad-hoc signs by default, which is fine for running Vibra and not
fine for *granting it permissions*. macOS pins a TCC grant to whatever identity
the bundle has, and an ad-hoc bundle has none — so the grant is pinned to the
exact code hash instead. Measured on 2026-09-21, the Automation grant's stored
requirement was literally `fade0c00...` followed by the cdhash:

```sh
codesign -d -r- /Applications/Vibra.app
# designated => cdhash H"83ed91aa1d4e9f84a698e8731fe64c37f5410d63"
```

Any rebuild that changes a byte of the binary invalidates that, and you get
"Vibra wants to control iTerm" again. Reverting the source does **not** undo it:
a release build is not byte-reproducible once the build cache has been
disturbed, so the old hash does not come back.

Signing with a stable certificate fixes it, and does not need an Apple account
or a network connection — a self-signed code-signing certificate in your login
keychain is enough:

1. **Keychain Access → Certificate Assistant → Create a Certificate…**
   Name it `vibra local signing`, Identity Type **Self Signed Root**, Certificate
   Type **Code Signing**. (Or generate one with `openssl` and
   `security import ... -T /usr/bin/codesign`.)
2. Build with it:
   ```sh
   make install SIGN_IDENTITY="vibra local signing"
   ```
   The first build prompts for keychain access. Choose **Always Allow**, or every
   later build stops and waits for the same dialog.

The designated requirement then names the certificate rather than the binary:

```sh
codesign -d -r- /Applications/Vibra.app
# designated => identifier "ai.silexlab.vibra" and certificate root = H"f067ca2a..."
```

and permissions survive rebuilds.

#### What this costs you

**The certificate is local to one machine, and deliberately not in this repo.**
It is a private key; committing one would hand anyone who clones the repo the
ability to sign as you. So:

- `SIGN_IDENTITY` is **opt-in and per machine**. A fresh clone, a second Mac and
  CI all get ad-hoc signing and behave exactly as before — nothing in the repo
  changes because you created a certificate.
- On a second machine, either **create another certificate** with the same steps
  (its own hash, its own one-time permission approvals over there), or export
  the first as a `.p12` and import it — which moves a private key between
  machines, so only do that if you are comfortable with that trade.
- Deleting it is the whole uninstall: remove `vibra local signing` from Keychain
  Access and build without `SIGN_IDENTITY`. You are back to ad-hoc, and back to
  re-approving after rebuilds. Nothing else to undo.

**Watch the expiry.** Certificate Assistant defaults to **365 days**. When it
lapses, signing fails and — because failure is fatal — your build stops, which
is at least loud. Set a longer validity when you create it; the `openssl` route
takes `-days 3650`.

**Signing failure fails the build.** It used to be a warning, which meant a
denied keychain prompt produced a quietly ad-hoc bundle that ran fine and then
mysteriously could not hold a permission. If the identity is missing or
unusable you now get:

```
error: codesign failed. The bundle would run but could not hold any
       permission: no notifications, no terminal jump-back.
       Check that SIGN_IDENTITY=... names a code-signing
       identity: security find-identity -p codesigning
make: *** [app] Error 1
```

The build also checks what it *produced*, not just codesign's exit code: asking
for an identity and silently getting ad-hoc back is the failure that hides best,
so that fails too.

**Permissions still need approving once**, on each machine, per target app
(iTerm2 and Terminal are separate grants). The certificate does not grant
anything — it makes the approval you give outlive rebuilds.

To clear the grant and be prompted again from scratch:

```sh
tccutil reset AppleEvents ai.silexlab.vibra
```

Only useful when you want to re-test the prompt, or when a grant is stuck
against a bundle you no longer have. It removes a working permission, so it
costs you one re-approval.

This is **not** a substitute for Developer ID signing and notarization, which is
what distributing a download would need — a fresh clone is still ad-hoc, so its
notifications are refused by default and its jump-back needs a manual grant.

## Testing note

Run tests with `make test` or `swift run VibraTests` — **not** `swift test`.

On a machine without Xcode, SwiftPM builds the suite as a loadable `.xctest`
bundle it has no harness to execute. `swift test` then prints `Build complete!`,
runs **zero** tests, and exits `0`. That silent false green is worse than having
no tests, so the suite is an ordinary executable that invokes swift-testing's
entry point and returns a real exit code. `make test` additionally asserts that
a non-zero number of tests ran and that the security canary was among them.

## Status

Early, but no longer expensive. Phase 0 of [the roadmap](ROADMAP.md) is
done: idle CPU went from ~97% to 0.0% and resident memory from 626 MB to
~61 MB, measured on a 488-file, 339 MB corpus.

| | before | after |
|---|---|---|
| idle CPU | ~97% | **0.0%** |
| RSS | 626 MB | **~61 MB** |
| cold start | 12.4s | **0.37s** |
| unchanged refresh | full re-parse | **0 bytes read** |

Run `make bench` to reproduce those numbers on your own corpus.

Current state is tracked in [docs/STATUS.md](STATUS.md); planned work,
with the reasoning behind each decision, in [docs/ROADMAP.md](ROADMAP.md).

Working against real data: the menu bar, all six adapters, state
classification, usage/cost accounting, and terminal jump-back. Not yet done:
Developer ID signing.

# Launch kit for v0.5.0

For the owner. Use it only after plan task 14 passes
(`docs/PLAN-2026-11-12-release-and-test-integrity.md`). Nothing here is posted
by an agent. Every claim below is backed by a test, a CI run or the README.

## Before you post, all of these must be true

- [ ] The `v0.5.0` release workflow log shows notarization `Accepted`.
- [ ] `xcrun stapler validate` passed on the DMG.
- [ ] Both `spctl` checks report accepted, source Notarized Developer ID.
- [ ] `lipo -archs` lists `x86_64` and `arm64`.
- [ ] The `TeamIdentifier` check passed (the log masks the value as `***`).
- [ ] The draft release carries `Vibra-0.5.0.dmg`, its `.sha256` and
      `docs/releases/v0.5.0.md` as the body. The `.sha256` matches a fresh
      download.
- [ ] A downloaded copy, still quarantined, opens without the
      unidentified-developer block.
- [ ] Vibra's Setup window reports notification authorization granted.
- [ ] The release body no longer opens with the "Draft" note from
      `docs/releases/v0.5.0.md`; rewrite it before publishing.
- [ ] You published the draft release yourself.
- [ ] The README and tap changes below are merged.

## Show HN draft

Title:

> Show HN: Vibra, see which of your coding agents read ~/.ssh or force-pushed

Body:

> Vibra is a macOS menu-bar app that reads the session files Claude Code,
> Codex and other coding agents already write on your Mac. It shows which
> session needs you, and it lists what agents did that you may not have
> sanctioned. That covers a credential file read, a write outside the
> workspace, a force push, a denied call that later ran, and a session with
> guardrails off.
>
> It installs no hooks or plugins into your agents and makes no network
> request. It is read-only and observes. It never blocks an agent. Each finding
> names its related category in the OWASP Top 10 for Agentic Applications
> 2026, and you can turn one into a local report draft.
>
> v0.5.0 is the first Developer ID signed and notarized DMG. It is open source
> under Apache-2.0.
>
> https://github.com/silex-ai-lab/silex_vibra

No test-edit line. On the owner's 30 days of sessions the test-edit sentence
fired 0 times (plan task 4), so it is not a launch claim.

## awesome-claude-code one-liner

The list takes submissions from a human only. Submit it yourself.

> [Vibra](https://github.com/silex-ai-lab/silex_vibra) - a local, read-only
> macOS menu-bar app that shows which Claude Code session needs you and audits
> agent activity (credential reads, outside writes, force pushes) with no hooks
> and no network.

## 20-second demo shot list

1. 0 to 4 s. The menu bar icon, then the menu open, with one session under
   Needs You.
2. 4 to 8 s. Click the row. Return to Session lands in that terminal.
3. 8 to 14 s. Review Agent Activity, with one credential-read finding and its
   "Related OWASP category" visible.
4. 14 to 20 s. Session Details with the Code checks row.

Record on a real Mac with live sessions. Show no real paths, prompts or
repository names.

## README and tap changes once the DMG is published

- README Quick start. Add the DMG download from the GitHub release as the
  first install option. Keep Homebrew and building from source.
- README Privacy and "Before you install". Remove the manual notification step
  that the ad-hoc signature required, only if the task 14 check confirms
  notifications are granted.
- The tap. A signed cask is separate work (ROADMAP P3.3) and is not part of
  this run. The source formula moves to 0.5.0 as before.

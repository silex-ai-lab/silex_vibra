# Vibra: landscape and distribution research (2026-11-12)

Star counts, licenses, and release dates come from the GitHub REST API (`gh api repos/<r>`, `/releases/latest`), queried 2026-11-12. Labels: **[V]** verified from the cited page or API, **[I]** inferred.

## 1. Landscape

### Session-status menu-bar apps (closest competitors)

| Tool | What it does | Stars | Data source | Network | License | Last release |
|---|---|---|---|---|---|---|
| [usedhonda/cc-status-bar](https://github.com/usedhonda/cc-status-bar) | Red/yellow/green menu-bar state for Claude Code and Codex, notifications, click-to-focus for Ghostty+tmux, iTerm2, VS Code family | 89 | **Installs hooks** in `~/.claude/settings.json` | "zero network requests", plus an optional iOS remote server | MIT | v1.10.5, 2026-10-31 |
| [cordwainersmith/Claudoscope](https://github.com/cordwainersmith/Claudoscope) | Menu bar plus dashboard. Fleet view of live sessions that flags ones waiting on you, cost estimates, scan for 10 secret patterns, spend alerts | 274 | Reads `~/.claude/projects` through FSEvents into SQLite. Claude Code and Cowork only. Its Agent Routing feature installs subagents into `~/.claude/agents/` | Local, except an update check | MIT | in homebrew/cask core ([API](https://formulae.brew.sh/api/cask/claudoscope.json)) |
| [molodykhvitaliy/agent-monitor](https://github.com/molodykhvitaliy/agent-monitor) | Claude Code and Codex status, 5 notification types, Codex limits, keep-awake | 0 | Hooks to a loopback HTTP endpoint | No calls to Anthropic or OpenAI | Apache-2.0 | v0.9.0, 2026-08-28. Ad-hoc signed, not notarized, same as Vibra |
| [gmr/claude-status](https://github.com/gmr/claude-status) | Menu bar plus widget, Claude Code only | 65 | Hooks plus file watching (from search summary) [I] | n/a | BSD-3 | v1.4.0, 2026-07-29 |
| [sotthang/so-agentbar](https://github.com/sotthang/so-agentbar) | Claude Code, Codex, Desktop, and Xcode sessions with token cost ([site](https://sotthang.github.io/so-agentbar/)) | 22 | n/a | n/a | MIT | v1.13.1, 2026-10-20 |
| [Cresswell-0301/ai-sessions](https://github.com/Cresswell-0301/ai-sessions) | Claude Code and Codex notifications, jump to the VS Code tab | 0 | n/a | n/a | none | no release |

### Usage and quota bars [V: API]
- [steipete/CodexBar](https://github.com/steipete/CodexBar): 23,139 stars, MIT, v0.84.0 on 2026-11-07, in homebrew/cask core ([API](https://formulae.brew.sh/api/cask/codexbar.json)). It shows quotas and does not track session state. Its most-reacted issues are keychain prompts (#108, #186, #340, about 35 reactions each), "becoming bloated" (#1364), and lag (#1274, #1321) ([search](https://github.com/steipete/CodexBar/issues?q=sort%3Areactions-%2B1-desc)).
- [tddworks/ClaudeBar](https://github.com/tddworks/ClaudeBar): 1,580 stars, Apache-2.0, v0.5.26 on 2026-11-09. Quotas for Claude, Codex, Antigravity, and Gemini.
- [ccusage](https://github.com/ccusage/ccusage): 19,420 stars, v20.0.50 on 2026-11-11. A CLI that reads local JSONL ([HN, 75 points](https://news.ycombinator.com/item?id=44610925)).
- [Maciek-roboblog/Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor): 8,801 stars, MIT, v4.0.0 on 2026-06-27. A terminal monitor.

### Multiplexers and orchestrators (they wrap or launch agents)
- [herdrdev/herdr](https://github.com/herdrdev/herdr): 50,612 stars, Apache-2.0, v0.9.5 on 2026-10-14. Describes itself as "the runtime your coding agents live on".
- [manaflow-ai/cmux](https://github.com/manaflow-ai/cmux): 28,778 stars, GPL-3.0 with BSL server parts, v0.65.2.2 on 2026-10-27. A Ghostty-based terminal with agent notifications through OSC sequences and `cmux hooks setup`, plus a Claude wrapper. Ships as a DMG with Sparkle and is in core cask. Demand signal: #1027 "'Running' and 'Needs Input' status indicators are flaky and unreliable" has 45 reactions ([issue](https://github.com/manaflow-ai/cmux/issues/1027)).
- [BloopAI/vibe-kanban](https://github.com/BloopAI/vibe-kanban): 28,668 stars, Apache-2.0, last pushed 2026-11-12.
- [smtg-ai/claude-squad](https://github.com/smtg-ai/claude-squad): 8,793 stars, AGPL-3.0, v1.0.20 on 2026-08-20. Runs on tmux plus worktrees [I, from description]. Its top issues are abandonment complaints (#214, #250).
- [stravu/crystal](https://github.com/stravu/crystal): 3,127 stars, MIT. Renamed to Nimbalyst, last release v0.3.5 on 2026-02-26.
- [nicknisi/fleet](https://github.com/nicknisi/fleet): 42 stars, a tmux dashboard fed by a Claude Code plugin and hooks ([listing](https://awesome.ecosyste.ms/projects/github.com%2Fnicknisi%2Ffleet)).
- [mercurialsolo/claudectl](https://github.com/mercurialsolo/claudectl): 204 stars, MIT, v0.92.4. A Rust TUI that reads `~/.claude/sessions` and can approve from the dashboard ([docs](https://docs.rs/crate/claudectl/0.19.0/source/README.md)).
- Conductor (commercial, Mac): parallel Claude Code and Codex agents in worktrees. Free tier, Pro at $50/month ([pricing](https://www.conductor.build/pricing)).

### Session viewers and audit tools
- [kenn-io/agentsview](https://github.com/kenn-io/agentsview): 6,432 stars, MIT, v0.47.0 on 2026-11-09. Local-first session search and analytics across 50+ agents.
- [sodiumsun/agenttrail](https://github.com/sodiumsun/agenttrail): 1,018 stars, MIT. Local observability with a live map of agent work, and it compares the declared plan with the actual diff ([EveryDev](https://www.everydev.ai/tools/agenttrail/llms.txt)). Agenttrail exists [V].
- [d-kimuson/claude-code-viewer](https://github.com/d-kimuson/claude-code-viewer): 1,304 stars. A web client.
- [safedep/gryph](https://github.com/safedep/gryph): 183 stars, Apache-2.0. Logs agent actions to SQLite through hooks ([safedep](https://safedep.io/gryph-ai-agent-audit-trail)).
- Single-shot transcript auditors with 0 stars: [cc-audit-log](https://github.com/yurukusa/cc-audit-log) flags force pushes, [sessionaudit](https://github.com/kriskimmerle/sessionaudit), and [clauditor](https://github.com/skettleson/clauditor).

### The gap Vibra fills
- **[I]** No tool I found combines all four of these: (a) live state across six agent families including Cursor, Copilot Chat, OpenCode, and Hermes, while every menu-bar competitor covers Claude Code and at most Codex; (b) **no hooks installed**, while cc-status-bar, agent-monitor, fleet, cmux, and gryph all install hooks; (c) zero egress, with no update check (Claudoscope makes one); (d) a continuous "Review Agent Activity" safety view plus Code checks inside the same status app. Claudoscope comes closest. It is Claude-only and it writes into `~/.claude/agents`.
- **[V] Demand for no-hooks:** cc-status-bar #19 says "Uninstall deletes unrelated commands in shared Claude hook groups", and #18 says "Codex setup can invalidate config.toml" ([issues](https://github.com/usedhonda/cc-status-bar/issues?q=is%3Aissue)).
- **[V] Demand for accurate state:** cmux #1027 (45 reactions).
- **[V] Demand for no credential access and low bloat:** CodexBar's keychain and bloat issues.
- **Things competitors have that Vibra lacks [V]:** notarized DMGs (cc-status-bar), core-cask installs (CodexBar, Claudoscope, cmux), Sparkle auto-update (cmux), quota and limit views (CodexBar, ClaudeBar, agent-monitor), spend alerts and secret detection (Claudoscope), and approve-from-dashboard (claudectl, which Vibra rules out by design). The top cmux asks are Linux (#330, 220 reactions) and remote/ssh workspaces (#1664).

## 2. Distribution

- **Gatekeeper policy [V]:** Homebrew 5.0.0 (2025-11-12) says "Casks without codesigning are deprecated" and "We will disable all Homebrew/homebrew-cask casks that fail Gatekeeper checks in September 2026". It also deprecated `--no-quarantine` ([blog](https://brew.sh/2025/11/12/homebrew-5.0.0/), [brew#20755](https://github.com/Homebrew/brew/issues/20755)). This is now in effect. The tic80 cask was disabled on 2026-09-01 with reason `fails_gatekeeper_check` ([TIC-80#3220](https://github.com/nesbox/TIC-80/issues/3220), filed 2026-11-11). Acceptable Casks requires apps that "must not require ... Gatekeeper to be disabled or bypassed" ([docs](https://docs.brew.sh/Acceptable-Casks)). Third-party taps are not covered by the core rule. **[I]** An own-tap cask of an ad-hoc app still works, but users hit the quarantine block, and the `--no-quarantine` workaround is going away.
- **Notability for core cask [V]:** 75 stars, 30 forks, or 30 watchers, raised to **225 stars / 90 forks / 90 watchers for a self-submission** ([policy](https://docs.brew.sh/Package-Acceptance-Policy)). Vibra (4 stars) does not qualify. Use your own tap until someone else submits it or the star count passes the bar.
- **Signing in CI [V]:** GitHub's guide uses the secrets `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, and `KEYCHAIN_PASSWORD`, imports the .p12 into a temporary keychain, and sets the partition list ([docs](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)). The provisioning profile is not needed for Developer ID [I]. Export a **Developer ID Application** certificate. A Developer ID Installer certificate is needed only for .pkg ([summary](https://www.electron.build/docs/notarization)).
- **notarytool auth:** use an App Store Connect API key (`.p8`, key ID, issuer ID) stored as three secrets. Electron's docs note API keys do not expire and need no 2FA ([electron-builder](https://www.electron.build/docs/notarization)) [V]. An app-specific password ties CI to one person's Apple ID [I].
- **Stapling [V]:** Apple says notary accepts UDIF disk images, signed flat pkgs, and ZIP, and "While you can notarize a ZIP archive, you can't staple to it directly". To use a ZIP, staple each item and re-zip it ([Apple](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)). **DMG vs zip [I]:** ship a stapled DMG for humans, which matches cc-status-bar and cmux. A cask can consume either.

### Launch evidence
- **[V]** Generic menu-bar Show HNs score 2 to 5 points: [Claudebar](https://news.ycombinator.com/item?id=47622239) 3, [AI Usage](https://news.ycombinator.com/item?id=49080227) 2, [rate-limit bar](https://news.ycombinator.com/item?id=47781940) 5. Differentiated launches score high: [cmux](https://news.ycombinator.com/item?id=47079718) 198 points / 77 comments, [Vibe Kanban](https://news.ycombinator.com/item?id=44533004) 195 / 132. **[I]** The angle must be the difference ("which of my agents read ~/.ssh or force-pushed, with no hooks and no network"), not "another menu bar".
- **[V]** awesome-claude-code (57,875 stars) takes submissions through the web issue form only. It needs 14+ days since the first commit with ongoing commits, or 100 stars. It wants a one-line description with no emojis and no sales tone, and the recommendation must come from a human ([CONTRIBUTING](https://github.com/hesreallyhim/awesome-claude-code/blob/main/CONTRIBUTING.md)). Vibra meets the age rule.

## Ranked actions

1. **Developer ID plus notarized, stapled DMG in GitHub Actions.** Why: it fixes the notification-authorization blocker, removes the quarantine step, and is required for any future core cask. Evidence: Homebrew 5.0 policy, the tic80 disable, the Apple stapling doc. Cost is $99/year for the Apple Developer Program [I].
2. **Make the own-tap cask (not the source formula) install the notarized DMG.** Why: brew users expect `--cask` for GUI apps, and core is out of reach below 225 stars for a self-submission. Evidence: the acceptance policy.
3. **A 15 to 30 second demo GIF at the top of the README** showing several agents changing state, the your-turn notification, the jump to the terminal, and one Review Agent Activity finding. Why: the field is crowded and visually similar, and the differentiator must show in seconds [I].
4. **Position on the gap.** Lead with "six agents, installs nothing, zero network, audits what agents did". Why: users complain about hook breakage and flaky state (cc-status-bar #18/#19, cmux #1027), and every rival covers at most two agents.
5. **Show HN with the security/audit angle, posted once item 1 ships.** Why: generic menu-bar posts get about 3 points, differentiated ones get about 200. Evidence: HN data above.
6. **Submit to awesome-claude-code through the issue form** (eligible now), then the r/ClaudeAI and r/cursor communities [I]. Reddit norms were not verified.
7. **Add a quota/limits panel from local data only** (Codex `app-server` the way agent-monitor reads it). Why: the most-starred adjacent tools are quota bars (CodexBar 23k, ClaudeBar 1.6k). Do this only if it can be done without network or keychain access, which CodexBar users complain about.
8. **Optional Sparkle-free update notice.** Defer it, because any update check breaks zero egress [I]. Rely on `brew upgrade` instead.

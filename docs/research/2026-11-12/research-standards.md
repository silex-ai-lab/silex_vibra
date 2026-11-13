# Standards and vendor surfaces Vibra could align with (research, 2026-11-12)

Labels: **V** = verified on the cited page during this session. **S** = secondary source only. **I** = my inference.

## 1. OpenTelemetry GenAI semantic conventions

- The GenAI conventions moved out of the core semconv repo. The old opentelemetry.io page now says they "have moved to the OpenTelemetry GenAI semantic conventions repository" (V, https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-agent-spans/). Secondary sources date the split to semconv v1.42.0, 12 June 2026 (S, https://www.dash0.com/knowledge/opentelemetry-genai-semantic-conventions-explained). The new repo shows no release and a "TODO" schema URL (V, https://github.com/open-telemetry/semantic-conventions-genai).
- Agent spans are status **Development**. Operations are `create_agent` (CLIENT), `invoke_agent` (INTERNAL, named `invoke_agent {gen_ai.agent.name}`), `invoke_workflow`, `invoke_{framework_entrypoint}` and `plan`. Key attributes are `gen_ai.agent.id`, `gen_ai.agent.name` (must be low cardinality) and `gen_ai.conversation.id` (only when the framework supplies one, no generated fallback) (V, https://github.com/open-telemetry/semantic-conventions-genai/blob/main/docs/gen-ai/gen-ai-agent-spans.md).
- Tool spans are `execute_tool {gen_ai.tool.name}`, kind INTERNAL, status Development. Required: `gen_ai.operation.name=execute_tool`, `gen_ai.tool.name`. Conditionally required: `error.type`, `gen_ai.tool.call.id`, `gen_ai.conversation.id`. Opt-in: `gen_ai.tool.call.arguments` and `.result`. There is also a `gen_ai.execute_tool.exception` event, a duration metric, and new "agent skills" and command-execution refinements that can carry executable name and exit code (V, https://github.com/open-telemetry/semantic-conventions-genai/blob/main/docs/gen-ai/execute-tool.md).
- No public stabilization timeline (S, https://www.greptime.com/blogs/2026-05-09-opentelemetry-genai-semantic-conventions).
- Gap (I): GenAI semconv has no attribute for a permission decision, an approval source or a policy finding. Vibra would need a vendor namespace such as `vibra.*` for those.

## 2. Vendor-native telemetry and hook surfaces

**Claude Code** (V, https://code.claude.com/docs/en/monitoring-usage)
- OTel is opt-in via `CLAUDE_CODE_ENABLE_TELEMETRY=1` plus `OTEL_METRICS_EXPORTER` / `OTEL_LOGS_EXPORTER` (`otlp`, `console`, `prometheus`, `none`). Traces need `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` and are beta.
- `claude_code.tool_decision` carries `tool_name`, `decision` (accept/reject), `source` in {`config`, `hook`, `user_permanent`, `user_temporary`, `user_abort`, `user_reject`}, `classifier_verdict`, `permission_mode`, `tool_use_id`. `claude_code.tool_result` carries `success`, `decision_source`, `tool_use_id`. `claude_code.api_request` carries token counts and `cost_usd`. Metrics include `claude_code.token.usage`, `cost.usage`, `code_edit_tool.decision`.
- No general file exporter is documented. `OTEL_LOG_RAW_API_BODIES=file:<dir>` writes API bodies plus `index.jsonl` (v2.1.274+).
- Hooks: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `PermissionDenied`, `Notification` (matcher `permission_prompt`), `Stop`, `SessionStart/End`, `SubagentStart/Stop`, `FileChanged`, and more. Every event gets `session_id`, `transcript_path`, `cwd`, `permission_mode` (`default`, `plan`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`) (V, https://code.claude.com/docs/en/hooks).
- Statusline script gets `session_id`, `transcript_path`, `cost.total_cost_usd`, `context_window.used_percentage`, `rate_limits` on stdin (V, https://code.claude.com/docs/en/statusline).

**OpenAI Codex CLI** (V, https://learn.chatgpt.com/docs/config-file/config-advanced)
- `[otel]` opt-in. `exporter = "none"` records but sends nothing, or `otlp-http` / `otlp-grpc`. Events: `codex.conversation_starts`, `codex.api_request`, `codex.sse_event`, `codex.user_prompt`, `codex.tool_decision`, `codex.tool_result`, `codex.guardian_assessment`, `codex.agent_response`. `log_user_prompt` defaults false.
- `notify` runs a program on `agent-turn-complete` with `thread-id`, `turn-id`, `cwd`, `last-assistant-message`. One adapter also reports `approval-requested` (S, https://docs.rs/mi6-core/0.2.8/src/mi6_core/framework/codex.rs.html).
- Hooks are on by default: `SessionStart`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `Pre/PostModelRequest`, `Stop`, `Interrupt`, and others. The docs state the transcript format "isn't a stable interface" (V, https://learn.chatgpt.com/docs/hooks).
- App-server is bidirectional JSON-RPC with `thread/start`, `turn/start`, `item/*` notifications and server-to-client approval requests `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`. A schema can be generated locally with `codex app-server generate-json-schema` (S, https://openai.com/index/unlocking-the-codex-harness, https://codex.danielvaughan.com/2026/03/28/codex-app-server-json-rpc-protocol/).

**Cursor**: hooks in `.cursor/hooks.json`, `~/.cursor/hooks.json`, `/etc/cursor/hooks.json`. Events include `beforeShellExecution`, `beforeMCPExecution`, `beforeReadFile`, `afterFileEdit`, `stop`, and newer `preToolUse`/`postToolUse`. Hooks answer allow/deny/ask (S, https://cursor.com/docs/hooks, https://blog.gitbutler.com/cursor-hooks-deep-dive). I did not find a Cursor OTel export.

**GitHub Copilot**: CLI and cloud agent hooks in `.github/hooks/*.json` and `~/.copilot/hooks/*.json`, version 1, events `sessionStart`, `sessionEnd`, `userPromptSubmitted`, `preToolUse`, `postToolUse`, `errorOccurred` (S, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-hooks-reference). VS Code agent hooks are Preview and "compatible with Claude Code and Copilot CLI hook formats" (S, https://code.visualstudio.com/docs/copilot/customization/hooks).

**OpenCode**: server plugins register `ctx.tool.hook("execute.before"|"execute.after")`, `ctx.permission.hook("evaluate")`, `ctx.shell.hook("create.before")` and subscribe to typed events (V, https://opencode.ai/docs/build/plugins/server). Plugins load from `.opencode/plugins/` and `~/.config/opencode/plugins/` (V, https://opencode.ai/docs/plugins/).

Pattern (I): all six vendors converged in 2025-2026 on a PreToolUse / PermissionRequest / PostToolUse hook shape, and Claude Code and Codex both now emit a `tool_decision` event with an approval source. That is the same fact Vibra reconstructs from transcripts today.

## 3. Trace, evidence and provenance formats

- **Agent Trace** (Cursor): v0.1.0, status RFC, January 2026. JSON trace record with `version`, `id`, `timestamp`, `files[].conversations[].ranges[]`, optional `vcs` (git/jj/hg/svn + revision), `contributor.type` in human/ai/mixed/unknown, `model_id`. Storage is deliberately undefined (local files, git notes, DB suggested). Partners include Cognition, Cloudflare, Vercel, Jules, Amp, OpenCode, Cline (V, https://agent-trace.dev/). Thoughtworks Radar "Assess", April 2026 (S, https://www.thoughtworks.com/radar/platforms/agent-trace).
- **OpenInference** (Arize): OTel-based, `openinference.span.kind` values include `AGENT`, `TOOL`, `LLM`, `EVALUATOR` (S, https://arize.com/docs/phoenix/tracing/concepts-tracing/otel-openinference/span-kinds).
- **Agent Client Protocol (ACP)**: JSON-RPC between editor and agent, with `session/request_permission` for tool authorization; a v2 RFD adds a title and structured subject to permission prompts (S, https://agentclientprotocol.com/protocol/v2/overview.md, https://agentclientprotocol.com/rfds/v2/permission-requests.md). Copilot CLI in ACP mode was reported to auto-approve without sending it (S, https://github.com/github/copilot-cli/issues/845).
- **MCP logging**: `notifications/message` with RFC 5424 levels; server-to-client only, says logs MUST NOT contain credentials (V, https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/logging). Not an audit format.
- **Git trailers**: no ratified standard. `Assisted-by:` is spreading (LLVM, kernel style); an IETF individual draft, draft-morrison-identity-attributed-commits-02 (August 2026), defines a trailer grammar (S, https://datatracker.ietf.org/doc/draft-morrison-identity-attributed-commits/, https://cc.bruniaux.com/guide/ai-traceability/).
- **in-toto / SLSA**: no AI-code predicate found. A custom predicate URI in an in-toto Statement is the extension path (S, https://slsa.dev/provenance/v0.2). I found no C2PA-for-code effort.
- **OWASP Top 10 for Agentic Applications 2026** (published 9 Dec 2025, V, https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/). Titles (S, https://www.giskard.ai/knowledge/owasp-top-10-for-agentic-application-2026): ASI01 Goal Hijack, ASI02 Tool Misuse, ASI03 Identity & Privilege Abuse, ASI04 Supply Chain, ASI05 Unexpected Code Execution, ASI06 Memory & Context Poisoning, ASI07 Inter-Agent Comms, ASI08 Cascading Failures, ASI09 Human-Agent Trust Exploitation, ASI10 Rogue Agents. Mapping (I): credential reads -> ASI03; denied-then-ran, writes outside workspace, force push -> ASI02; bypass/unrestricted sessions -> ASI03/ASI09; unchecked edits (no Code check) -> ASI05/ASI08.
- **NIST**: CAISI launched the AI Agent Standards Initiative on 17 Feb 2026; RFI NIST-2025-0035 on agent security; NCCoE concept paper on agent identity and authorization (OAuth, SPIFFE, MCP); SP 800-53 COSAiS overlays for agents still in development (S, https://labs.cloudsecurityalliance.org/research/csa-research-note-nist-ai-agent-standards-initiative-2026032/). I found no CISA guidance naming coding-agent behaviours specifically.

## 4. What a read-only, offline tool can use

| Option | Fits Vibra's rules? | Why |
|---|---|---|
| Write a local OTLP-JSON file of `invoke_agent` / `execute_tool` spans plus `vibra.finding` events derived from transcripts | Yes | Pure file output; no egress, no agent change. Consumer chooses to ship it (I). |
| Write Agent Trace records (file or local dir) from edit tool calls in transcripts | Yes, partially | Vibra knows file, model, session; exact line ranges need diff reconstruction (I). |
| Map findings to OWASP ASI IDs in incidents.json | Yes | Metadata only (I). |
| Emit an in-toto Statement with a `vibra` predicate over a commit SHA, unsigned | Yes | Signing with a local key is offline; no predicate standard exists yet (I). |
| Read files vendors already write: Claude transcripts, Codex rollouts, Claude `OTEL_LOG_RAW_API_BODIES=file:` dir | Yes | Read-only. Codex warns its transcript format is unstable (V, learn.chatgpt.com/docs/hooks). |
| Receive Claude/Codex OTel via a localhost OTLP receiver | Borderline | No internet egress, but it listens on a socket and the user must set env vars or `[otel]`; Vibra itself installs nothing (I). |
| Hooks (PreToolUse, PermissionRequest), Cursor/Copilot hooks, OpenCode plugins | No | Requires installing into agents, and hooks can approve prompts. |
| ACP client, Codex app-server client | No | Vibra would become the approver. |
| Remote OTLP export, MCP logging | No | Network or agent integration. |

## Gaps and caveats
- Vendor doc pages fetched 2026-11-12; Claude Code and Codex move weekly.
- Cursor and Copilot details are from docs snippets and secondary sources, not full page reads.
- OWASP ASI titles come from a secondary page; the OWASP page itself only offers a PDF download.

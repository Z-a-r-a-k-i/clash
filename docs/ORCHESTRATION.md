# Agent Orchestration

Multi agent coordination for clash. A coordinator agent plans work, dispatches workers, and reviews PRs. Workers execute tasks in isolated repo clones.

## Terminology

| Term | Definition |
|------|-----------|
| **Coordinator** | Agent that plans, delegates, reviews, and maintains project context. Edits MD files (plan tree, docs) but delegates code changes to workers. |
| **Worker** | Agent that executes a task: writes code, runs tests, creates a PR. |
| **Team** | A coordinator and N workers on the same project. |
| **Clone slot** | A directory containing a clone of the repo. The source repo and `{repo}-wt{N}` siblings are all clone slots. |

## Core rules

1. **SDK only.** All orchestrated agents run via the Claude Agent SDK. No terminal CLI mode for coordination.
2. **1 agent session = 1 clone slot.** Every agent gets its own directory. The source repo is one slot, same as `clash-wt1`, `clash-wt2`, etc.
3. **Markdown is the configuration layer.** Permissions, task context, and behaviour rules are defined in MD files (this repo's `AGENTS.md`, `plan/` nodes, coordinator crafted task briefs). Not in protocol.
4. **Coordinator plans and reviews; workers code.** The coordinator reads, searches, runs dev servers, thinks, and edits MD files. It delegates implementation to workers.
5. **Self test before escalate.** Workers loop (implement → test → fix) until passing before creating PRs.
6. **Hard block destructive actions only.** Force push, branch delete, irreversible operations. Everything else is markdown enforced.

## Clone management

```text
games/
├── clash/             <- source repo, also a clone slot
├── clash-wt1/         <- worker clone
├── clash-wt2/         <- worker clone
└── clash-wt3/         <- worker clone
```

- Each clone is a full `git clone` (not a worktree). Worktrees share the `.git` database and cause branch lock issues.
- Workers create their own feature branches inside their clone.
- Clone naming: `{repo}-wt{N}`.

## Inter agent communication

The coordinator and workers communicate through the orchestration server (e.g., termwatch). Direct agent-to-agent communication is mediated by the server's message router; no peer to peer.

Patterns:

- **Coordinator → Worker:** task brief, course correction, follow up directive.
- **Worker → Coordinator:** status update, question, completion report.
- **Coordinator → User:** escalation when something can't be decided autonomously (architecture choice, design ambiguity).

## See also

- [docs/PARALLEL-AGENTS.md](PARALLEL-AGENTS.md) — file conflict and merge rules.
- termwatch's `docs/ORCHESTRATION.md` — full team management design that clash inherits the model from.

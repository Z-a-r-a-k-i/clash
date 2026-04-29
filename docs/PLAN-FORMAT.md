# Plan Tree Format

Version 0.1 (draft)

A format for tracking projects as a tree of markdown files. Each file is a node.
Nodes have a status and optional dependencies. Any tool that edits markdown can
edit the plan.

## Goals

1. **Progressive elaboration.** Nodes can start as one-line stubs and become
   detailed over time. Parents can be vague while children are detailed. You
   never need to finish specifying the whole plan before you can start work.
2. **Parallel execution.** Any node that is "ready" is dispatchable. Multiple
   ready nodes can be worked in parallel, by humans or agents.
3. **Standard tools only.** Markdown plus YAML frontmatter plus filesystem
   directories plus git. No proprietary editor, no database, no lock-in. Any
   markdown editor and any git client is a full editor for the plan.
4. **Agent-collaborative.** AI agents read the tree, edit nodes, ask clarifying
   questions, claim work, and mark completion by editing files. No special
   protocol required on day one.

## Non-goals

- Not a ticketing system. No assignees, due dates, SLAs, priorities as
  first-class fields. If you need those, put them in the body.
- Not a project management methodology. No Scrum, no Kanban ceremonies, no
  phases. The format is a data shape, not a process.
- Not a spec-driven development framework. You are not required to specify
  everything before executing. The opposite, in fact.
- Not a replacement for design documents, ADRs, or technical writing. Those
  live in the body of nodes where relevant, or alongside.

## Directory Layout

```
plan/
├── AGENTS.md                     # Short instructions for agents (see below)
├── README.md                     # Root node of the tree
└── <area>/                       # Compound node (a directory)
    ├── README.md                 # The compound node's own file
    ├── <leaf>.md                 # Leaf node
    └── <sub-area>/               # Nested compound node
        ├── README.md
        └── <leaf>.md
```

Rules:

- **A directory is a compound node.** It contains child nodes (other files or
  subdirectories).
- **`README.md` inside a directory is that directory's own node file.** It has
  frontmatter and a body just like any other node. It represents the compound
  node itself, not a separate thing.
- **A plain `.md` file (not named `README.md`) is a leaf node.** It has no
  children.
- **Nesting is unlimited.** Go as deep as the problem needs. Make the top level
  as wide or as narrow as you want.
- **Filenames are the node identifier.** Use kebab-case. Renaming a file is
  fine; git tracks the move and relative paths in other nodes can be updated
  in the same commit.

## Node File Structure

Every node is a markdown file with YAML frontmatter:

```markdown
---
status: ready
---

# Node title

Body in plain markdown. Whatever you need.
```

The minimum viable node is two lines of frontmatter, one heading, and a body.

## Frontmatter Schema

Three fields total. One required, two optional.

### Required

- **`status`** — one of `stub | sketch | ready | doing | done`

### Optional

- **`depends_on`** — list of relative paths to other nodes that must be `done`
  before this node is effectively ready. Use only for cross-branch dependencies;
  parent-child relationships are implicit in the directory structure.
- **`questions`** — list of unanswered questions from agents or humans that
  block further progress. See the Agent Question Loop section.

Example with all fields:

```yaml
---
status: sketch
depends_on:
  - ../auth/token-refresh.md
  - ../../observability/sentry.md
questions:
  - id: q1
    asked_by: claude
    asked_at: 2026-04-10T14:00:00Z
    question: Should the readiness probe fail or report if migrations are pending?
---
```

Everything else is intentionally out of scope. If you want to track artifacts
(PR links, commit hashes, test runs), put them in the body as markdown. Git
already tracks history.

## Status Lifecycle

Five states. Transitions are not enforced — you can go from any state to any
other state by editing the file. The semantics are:

| Status   | Meaning                                                          | Dispatchable?  |
|----------|------------------------------------------------------------------|----------------|
| `stub`   | Placeholder. Title only, no real content. "Remember this later." | No             |
| `sketch` | Context and ideas exist but not actionable yet. Rough notes.     | No             |
| `ready`  | Enough detail that an agent or human can start work.             | Yes            |
| `doing`  | An agent or human has claimed it and is actively working.        | No (claimed)   |
| `done`   | Completed. Acceptance criteria met. Stays as historical record.  | No             |

### Key rules

- **A compound node's status is independent of its children's statuses.** A
  parent can be `sketch` while its children are `ready`, `doing`, or `done`.
  Parent detail and child detail are independent. This is the core of
  progressive elaboration.
- **`stub` is free.** Use it for any idea you want to remember without
  committing to. Deleting a stub later is costless.
- **Promotion from `sketch` to `ready` is a human call** unless an agent has
  filled in enough detail and explicitly requests promotion.
- **Superseded nodes stay in place as `done`** with a note in the body linking
  forward to the replacement. Git history has the rest.
- **A compound node does not need to be explicitly marked `done`** when all its
  children are done. If you want to, fine, but it is not required.

## Dependencies

Most dependencies are implicit:

- **Parent contains children.** Directory structure is the primary dependency
  signal.
- **Sibling order within a directory.** If `b.md` depends on `a.md` and both
  live in the same directory, put the dependency in `b.md`'s `depends_on`.

Use explicit `depends_on` only for **cross-branch dependencies**:

```yaml
---
status: ready
depends_on:
  - ../../auth/token-refresh.md
  - ../../observability/sentry.md
---
```

Paths are relative to the node file. If you rename a target file, update the
referencing file in the same commit.

## Ready Computation

A node is **effectively ready** when:

1. `status` is `ready`, AND
2. Every path in `depends_on` resolves to a node with `status: done`.

A node is effectively ready regardless of whether its parent is `sketch` or
`done`. Parent state does not gate child readiness.

Quick and dirty query:

```bash
# All nodes marked ready (does not check depends_on)
rg -l '^status: ready$' plan/

# Parse frontmatter properly (with yq)
fd -e md . plan/ -x yq -r 'select(.status == "ready") | input_filename' {}
```

A small CLI (optional) can check `depends_on` resolution and return only
effectively-ready nodes.

## Agent Question Loop

When an agent picks up a node and discovers it is missing detail needed to
proceed, the format provides a structured way to ask without blocking other
work:

1. **Agent adds a question to the node's `questions` frontmatter array:**

   ```yaml
   questions:
     - id: q1
       asked_by: claude
       asked_at: 2026-04-10T14:23:00Z
       question: |
         The acceptance criteria mention "structured logging" but don't
         specify the logging library. Should we use zap, slog, or zerolog?
   ```

2. **Agent flips `status` back to `sketch`** (or leaves it as `ready` if it can
   continue partially on other aspects).

3. **Agent commits the question.**

4. **Human (or another agent) answers by editing the body** to resolve the
   question, then deletes the question entry from the array.

5. **When all questions are resolved**, human or agent promotes status back to
   `ready`.

Unresolved questions block promotion to `ready`. Resolved questions get
deleted; git keeps the history.

## Done Criteria

Mechanically, a node is done when `status: done`. That is the only requirement.

For discipline, a leaf node body should include an acceptance criteria section
(prose or checkboxes) that a human or agent reviews before flipping to `done`.
This is a convention, not a hard rule.

```markdown
## Done when

- [ ] /ready verifies DB pool is alive
- [ ] /ready verifies hub is running
- [ ] /ready verifies migrations applied
```

When flipping to `done`, check the boxes rather than deleting the list. The
record of what was required stays in the file.

Artifacts (PR links, commit hashes, test runs) can go in the body under an
`## Artifacts` heading or similar. Not in frontmatter. Not required.

## Rules for Agents

If you are an AI agent reading this tree:

1. **Read `plan/README.md` first.** It is the root of the tree and explains the
   project-level goals.
2. **To find work, look for nodes with `status: ready`.** Verify that every
   path in `depends_on` resolves to a node with `status: done`. If not, the
   node is not effectively ready — pick a different one.
3. **To claim a node, set `status: doing` and commit immediately.** This
   signals other agents not to double-claim.
4. **If the node is missing detail, do not guess.** Add an entry to
   `questions`, revert `status` to `sketch` (or leave it `ready` if you can
   proceed partially), and commit.
5. **To mark complete, set `status: done`**, check any acceptance checkboxes in
   the body, optionally add artifact links under an `## Artifacts` heading, and
   commit.
6. **Never delete a `done` node.** It is historical record. If a node is
   replaced by a different approach, mark it `done` with a pointer to the
   replacement in the body.
7. **Do not reshape the tree without human approval.** Moving directories,
   renaming nodes, changing parent-child relationships — ask first. You can add
   new leaf nodes freely in existing directories.
8. **When editing a `sketch` to add detail, do not self-promote to `ready`**
   unless explicitly instructed. Leave it as `sketch` or lower until a human
   confirms readiness.
9. **In PRs, update any plan nodes relevant to the work.** Mark them `done` if
   finished. Add artifact links. Never leave a PR that implements a `doing`
   node without flipping its status.

## Rules for Humans

Nothing is enforced, but these habits keep the tree useful:

- **Scribble stubs freely.** Costs nothing. Forgotten ideas are worse than
  messy trees.
- **Promote `sketch` → `ready` only when you would be comfortable handing the
  node to someone who has never seen the project before.** That is the
  calibration.
- **Resist the urge to fully specify upfront.** Progressive elaboration is the
  point. You will learn things while working that will change the sketches.
- **Let git be the history.** Do not maintain manual changelogs inside nodes.

## Examples

### Stub node

```markdown
---
status: stub
---

# Cross-project plan aggregation

Termwatch should eventually aggregate plan trees across all projects.
Details later.
```

### Sketch node

```markdown
---
status: sketch
---

# Sentry integration

Add Sentry for server crash reporting. Wire into panic recovery, unhandled
errors, background goroutine failures.

## Open questions

- Initialize at server startup or lazily on first error?
- Scrub user IDs and session IDs from events? What is the privacy policy?
- Free tier or paid? Who owns the account?
```

### Ready leaf

```markdown
---
status: ready
---

# Readiness endpoint

Current `/health` returns static "ok" without checking anything. Add `/ready`
that verifies real readiness. Keep `/health` as a simple liveness probe.

## Done when

- [ ] /ready verifies DB pool is alive
- [ ] /ready verifies hub is running
- [ ] /ready verifies migrations have been applied
- [ ] /ready returns 503 if any check fails, 200 if all pass
- [ ] /health unchanged
```

### Doing node

```markdown
---
status: doing
---

# Readiness endpoint

... same body as when it was ready ...
```

### Done node

```markdown
---
status: done
---

# Panic recovery in hub goroutines

Per-iteration recovery in loops, function-level in one-shot goroutines,
structured error logging with stack traces.

## Done when

- [x] Recovery in all hub goroutines
- [x] Structured logging with stack traces
- [x] Per-iteration recovery in loops

## Artifacts

- PR #448
```

### Compound node (directory README.md)

```markdown
---
status: sketch
---

# Observability and Deployment

Harden server for production: readiness probes, crash reporting, metrics,
structured logging. Foundation for future per-agent metrics.

Readiness and Sentry are ready to implement. Prometheus metrics and
WebSocket lifecycle logging are still being thought through.
```

### Node with cross-branch dependency

```markdown
---
status: ready
depends_on:
  - ../../auth/token-refresh.md
---

# Share token expiration enforcement

Enforce share token expiration in the DB query, not just app code.

## Done when

- [ ] GetShareByTokenHash includes expires_at > NOW() filter
- [ ] All code paths funnel through that query
- [ ] Tests confirm expired tokens are rejected at the DB layer
```

## Minimum Tooling

Zero tooling is required. You can use this format today with:

- `git` (or `jj`)
- Any markdown editor: vim, VS Code, Obsidian, Cursor, Claude Code, etc.
- `rg` or `grep` for queries
- GitHub's or Forgejo's native rendering for browsing

Optional enhancements, to be built only when friction justifies them:

- A small CLI (`plantree` or similar) that validates frontmatter, computes
  effective readiness, and lists dispatchable leaves.
- An MCP server that exposes the tree as a queryable resource for agents.
- A pre-commit hook that lints frontmatter schema.
- A visualization layer (termwatch) that renders the DAG, shows per-node
  status, supports AI-mediated editing, and integrates dispatch.

None of those are required. The format is the product; the tools are optional
interfaces.

## Versioning This Document

This format is at version 0.1 (draft). Changes to the format will bump the
version. Breaking changes bump the major version. The format is intentionally
minimal so changes should be rare.

If you need to evolve a node beyond what the current version supports, open a
discussion about extending the format. Do not add non-standard fields to
frontmatter — if a field is worth having, it should be in the format for
everyone.

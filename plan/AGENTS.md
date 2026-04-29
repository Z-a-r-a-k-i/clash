# Plan Tree — Agent Entry Point

This directory is a Plan Tree: a hierarchical collection of markdown files where each file is a node in the project plan. Each node carries a `status` in its YAML frontmatter.

## Read this first

- `./README.md` — the root node with project level context.
- `../docs/PLAN-FORMAT.md` — the full format specification (frontmatter fields, status semantics, claim rules).
- `../AGENTS.md` — repo level architecture and coding rules.

## Essential rules for agents

1. **To find work**, look for nodes with `status: ready` whose `depends_on` are all `done`.
2. **To claim a node**, set `status: doing` and commit immediately.
3. **If the node is missing detail**, add a question to its `questions:` frontmatter array and revert `status` to `sketch`. Do not guess.
4. **To mark complete**, set `status: done`, check acceptance checkboxes in the body, add artifact links, commit.
5. **Never delete a `done` node.** It is historical record.
6. **Do not reshape the tree** (move/rename directories, restructure parent-child relationships) without human approval. Adding new leaf nodes in existing directories is fine.
7. **In any PR that finishes work in the tree, update the relevant plan nodes.** Never leave a PR that implements a `doing` node without flipping its status.

Full rules and examples: `../docs/PLAN-FORMAT.md`.

## Reconciliation

The plan tree is not enforced in real time. Agents are encouraged to update nodes during their PRs, but the authoritative sync mechanism is periodic reconciliation: an agent reads git history, compares commits to plan nodes, and proposes updates as a diff for human review.

Run reconciliation when picking up new work (so `ready` reflects reality), before a review session, or whenever the plan feels stale.

### Prompt template

```text
Reconcile the plan tree with the codebase.

1. Find the last sync point. Run `git log --oneline -- plan/` and identify the
   most recent commit that updated node statuses (not just added new nodes).
   If unclear, list candidates and ask me to pick.

2. For each commit from the sync point to HEAD, run `git show --stat <sha>`
   and read the message. For each commit, decide:

   - Does it complete work tracked in plan/? Find the matching node(s) by
     grep and by code path concerns. Propose flipping `status` to `done`,
     checking off relevant acceptance checkboxes, and adding the PR number
     under `## Artifacts`.
   - Does it partially ship work? Propose flipping to `doing`, checking
     off what's done, and noting what remains in the body.
   - Does it implement something not yet tracked? Flag it with a proposed
     new node location and a one line description.
   - Pure maintenance (docs, tests, refactor with no plan impact)? Skip.

3. Produce a unified diff of proposed changes to plan/. Do NOT apply it;
   show me the diff and any flagged commits that need human decisions.

4. List every commit you reviewed with one of these verdicts: matched,
   partial, untracked, maintenance. So I can verify coverage.

Use standard git and file reading only. Make no changes until I approve.
```

# Parallel Agent Work

Two levels of parallelization.

## Level 1: Task tool (research only)

Use the Task tool to spawn subagents for parallel research within one PR:

- Good for: exploring codebase, finding patterns, reading docs simultaneously.
- Subagents return findings; main agent synthesizes and writes code.
- All work feeds into ONE PR.
- Don't use subagents for actual file editing; they can't coordinate writes.

## Level 2: Isolated clones (parallel development)

For parallel work on different branches and PRs, use separate full clones:

```bash
git clone git@github.com:Z-a-r-a-k-i/clash.git ../clash-wt1
```

- Never use git worktrees; they share the `.git` database and cause branch lock issues.
- Each agent creates its own feature branch and PR.
- Isolated clones have zero interdependencies; each agent can checkout any branch freely.
- Clone naming convention: `{repo}-wt1`, `{repo}-wt2`, etc.

## Avoiding conflicts in parallel work

Parallel agents can modify the **same file** as long as they work on **different sections** (different methods, different scenes, different proto messages). Git can auto merge additions to different parts of a file.

The rule: don't have two agents modify the **same lines or methods**, not the same file.

Conflict resolution: resolve in the most reasonable way; ask the user if unsure.

Merge order: first PR ready merges first; other agents rebase onto updated main.

## Coordination model

See [docs/ORCHESTRATION.md](ORCHESTRATION.md) for the coordinator/worker design.

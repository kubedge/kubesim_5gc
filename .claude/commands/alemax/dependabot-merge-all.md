---
name: "ALEMAX: Dependabot merge-all"
description: Merge several Dependabot PRs in sequence, auto-rebasing each after the previous one lands (squash-merging one stales the rest via context drift). Composes /alemax:dependabot-merge per PR. Works from any repo with a GitHub remote.
category: Workflow
tags: [workflow, alemax, dependabot, github]
---

## Governance preamble (run BEFORE any other step)

This command operates on **multiple GitHub PRs in the current repo** — it posts `@dependabot rebase` comments and squash-merges each. Outward-facing GitHub mutations, but exactly what the operator asked for by passing a list of PR numbers they've decided to accept. No branch / PR of our own; nothing under `openspec/**` is touched.

Before doing anything else:

1. Run `gh auth status` (authentication) and `git remote get-url origin` (GitHub remote present).
2. Works from any branch in any repo with Dependabot PRs — no branch restrictions.

Once preflight passes, **delegate the rest to the `alemax-dependabot-merge-all` skill** (`.claude/skills/alemax-dependabot-merge-all/SKILL.md`), which composes `alemax-dependabot-merge` per PR.

---

## Context guard

Declares `context: either` — runs from the meta-repo OR any project clone. Acts on whichever repo the operator is currently in.

---

## Input

The arguments are the PR numbers to merge, in order:

```
/alemax:dependabot-merge-all 41 42 43
```

If none are given, the skill offers to discover open Dependabot PRs (`gh pr list --author app/dependabot`) and confirm the ordered set before acting.

## Behavior

Merge the first PR (short-circuit if already mergeable, else rebase-loop). Then for each subsequent PR, run the full `@dependabot rebase` + bounded-poll + squash-merge loop — necessary because the prior merge flips same-file PRs to DIRTY via context-line drift. **Stops on the first non-recoverable failure** (real conflict, branch protection, poll timeout) and always ends with a state-of-all-PRs summary.

## Safety

Refuses the batch if **any** listed PR is not a Dependabot PR (no partial processing of a mixed set without operator say-so). Assumes each bump is already accepted in principle; never overrides branch protection.

## When NOT to use this command

- **A single Dependabot PR** — use `/alemax:dependabot-merge <#>`.
- **PRs across different files** — no context drift; they merge independently.
- **Unreviewed bumps** — review first.

## Cross-links

- `.claude/skills/alemax-dependabot-merge-all/SKILL.md` — full skill body.
- `.claude/commands/alemax/dependabot-merge.md` — the per-PR primitive it composes.
- `openspec/specs/alemax-dependabot-skills/spec.md` — behavioral spec.
- `meta/docs/ALEMAX-SKILLS.md` — family conventions.

---
name: "ALEMAX: Dependabot merge"
description: Unblock and merge a single stale Dependabot PR — comment `@dependabot rebase`, wait for the bot to push, then squash-merge. Handles the mergeStateStatus=UNKNOWN staleness. Works from any repo with a GitHub remote.
category: Workflow
tags: [workflow, alemax, dependabot, github]
---

## Governance preamble (run BEFORE any other step)

This command operates on a **GitHub PR in the current repo** — it posts a comment (`@dependabot rebase`) and squash-merges the PR. Both are outward-facing GitHub mutations, but they are exactly what the operator asked for by invoking the command with a PR number they've decided to accept. No branch / PR of our own is created; nothing under `openspec/**` is touched, so the canonical-only rule does not apply.

Before doing anything else:

1. Run `gh auth status` to confirm authentication, and `git remote get-url origin` to confirm a GitHub remote exists.
2. The skill works from any branch in any repo with Dependabot PRs — no branch restrictions.

Once preflight passes, **delegate the rest to the `alemax-dependabot-merge` skill** (`.claude/skills/alemax-dependabot-merge/SKILL.md`).

---

## Context guard

This command declares `context: either` — it runs from the meta-repo OR any project clone (both can have Dependabot PRs). It acts on whichever repo the operator is currently in.

---

## Input

The argument after `/alemax:dependabot-merge` is the PR number:

```
/alemax:dependabot-merge 42
```

If omitted, the skill asks for it.

## Safety

The skill **refuses non-Dependabot PRs** (it only knows how to drive `@dependabot rebase`) and **assumes the operator has already accepted the bump in principle** — it performs the merge mechanics, not the review decision. It short-circuits straight to the merge when the PR is already `MERGEABLE`, and never overrides branch protection.

## When NOT to use this command

- **Several Dependabot PRs to merge in sequence** — use `/alemax:dependabot-merge-all <#> <#> …` (merging one stales the rest via context drift; the batch skill re-rebases each).
- **A non-Dependabot PR** — merge it manually or with the appropriate tool.
- **You haven't reviewed the bump** — review first, then invoke.

## Cross-links

- `.claude/skills/alemax-dependabot-merge/SKILL.md` — full skill body.
- `.claude/commands/alemax/dependabot-merge-all.md` — the batch companion.
- `openspec/specs/alemax-dependabot-skills/spec.md` — behavioral spec.
- `meta/docs/ALEMAX-SKILLS.md` — family conventions.

---
name: alemax-dependabot-merge
description: Unblock and merge a single stale Dependabot PR. Stale bumps sit at mergeStateStatus/mergeable UNKNOWN because GitHub stops recomputing mergeability after ~a week; the fix is always the same — comment `@dependabot rebase`, wait for the bot to push the rebased commit, then squash-merge. This skill runs that 4-step loop with a bounded poll. Works from any git repo with a GitHub remote (meta-repo or project clone). Assumes the operator has already accepted the bump in principle — it handles the merge mechanics, not the review decision.
license: MIT
compatibility: Requires `gh` (authenticated) + `git`. Declares `context: either` — runs from the meta-repo OR any project clone. Posts a comment and merges a PR (outward-facing); short-circuits when the PR is already mergeable.
context: either
metadata:
  author: alemax
  version: "1.0"
---

## Wraps

No shell script. The workflow is a bounded `gh` CLI loop: check mergeability → (if stale) comment `@dependabot rebase` → poll until GitHub recomputes → squash-merge. This is the per-PR primitive that `/alemax:dependabot-merge-all` composes for a batch.

## The stale-Dependabot story

A Dependabot PR older than ~a week reports `mergeStateStatus: UNKNOWN, mergeable: UNKNOWN` even when nothing conflicts — GitHub simply stops recomputing mergeability for old PRs. Operators discover this only at merge time, after wasted polling. The unblock is mechanical and always identical: comment `@dependabot rebase`, wait for the bot to force-push a freshly-rebased commit (which makes GitHub recompute), then merge. This skill encodes that loop so the operator types one command instead of hand-driving the round-trip.

## When NOT to use this skill

- **The PR isn't from Dependabot** — the skill refuses (different bots use different comment commands; out of scope).
- **You haven't decided to accept the bump** — this skill does the *merge mechanics*, not the review. Review the changelog/diff first; invoke this once you've decided to take it.
- **You have several Dependabot PRs to merge in sequence** — use `/alemax:dependabot-merge-all <#> <#> …` instead; merging one flips the others to DIRTY (context-line drift) and the batch skill re-rebases each.

## Steps

### Step 0 — Preflight

Resolve the PR number from the argument (`/alemax:dependabot-merge 42` → `42`). If absent, ask. Confirm `gh auth status` succeeds and the current repo has a GitHub remote.

### Step 1 — Inspect + safety-gate

```bash
gh pr view <#> --json number,title,author,state,isDraft,mergeStateStatus,mergeable
```

- If `state != OPEN` → report and stop (already merged/closed).
- **Safety gate:** if `author.login` is not `app/dependabot` (or `dependabot[bot]`) → refuse: "PR #<#> is not a Dependabot PR; this skill only drives `@dependabot rebase`. Merge it manually or with the appropriate tool."
- **Short-circuit:** if `mergeable == MERGEABLE` and `mergeStateStatus == CLEAN` → skip straight to Step 4 (no rebase needed).
- If `mergeStateStatus == DIRTY`/`CONFLICTING` → the PR has a real conflict a rebase won't fix cleanly; surface it and let the operator decide (a rebase *may* still help if the conflict is pure context drift — offer to try Step 2 once).

### Step 2 — Trigger the rebase

```bash
gh pr comment <#> --body "@dependabot rebase"
```

Announce: "Posted `@dependabot rebase` on #<#>; waiting for the bot to push the rebased commit."

### Step 3 — Poll until GitHub recomputes (bounded)

Poll `gh pr view <#> --json mergeStateStatus,mergeable,headRefOid` every ~20s, up to ~3 minutes (≈9 polls). Watch for `mergeStateStatus` leaving `UNKNOWN` (and ideally `headRefOid` changing, confirming the bot force-pushed):

```bash
for i in $(seq 1 9); do
  read -r mss mrg < <(gh pr view <#> --json mergeStateStatus,mergeable --jq '"\(.mergeStateStatus) \(.mergeable)"')
  echo "poll $i: mergeState=$mss mergeable=$mrg"
  [ "$mss" != "UNKNOWN" ] && break
  sleep 20
done
```

- If it becomes `CLEAN`/`MERGEABLE` → Step 4.
- If it becomes `DIRTY`/`CONFLICTING` → the rebase surfaced a real conflict; surface it and stop (operator resolves).
- **Timeout (still UNKNOWN after ~3 min):** do NOT merge. Report the final state and options: the bot may be slow/rate-limited, or the PR may be superseded. Suggest re-running the skill or checking the PR's timeline for a `@dependabot` reply.

### Step 4 — Merge

```bash
gh pr merge <#> --squash --delete-branch
```

Squash-merge (the repo convention) and delete the head branch. Confirm the merge SHA. Done.

## Edge cases

- **`@dependabot rebase` already in flight** — if the operator (or a prior run) already triggered a rebase, Step 2's comment is harmless (Dependabot debounces); the poll still applies.
- **PR gets superseded mid-poll** — Dependabot occasionally closes a PR and opens a newer one. If Step 3 sees `state` flip to `CLOSED`, stop and report the superseding PR number if discoverable.
- **`mergeable` never leaves UNKNOWN but `mergeStateStatus` is `BLOCKED`** — required checks/reviews aren't satisfied; this skill does not override branch protection. Report the blocking requirement.

## Cross-links

- `.claude/skills/alemax-dependabot-merge-all/SKILL.md` — the batch wrapper that composes this per-PR loop.
- `openspec/specs/alemax-dependabot-skills/spec.md` — the behavioral spec for both skills.
- `meta/docs/ALEMAX-SKILLS.md` — the `/alemax:*` family conventions.

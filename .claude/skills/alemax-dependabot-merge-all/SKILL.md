---
name: alemax-dependabot-merge-all
description: Merge several Dependabot PRs in sequence, auto-rebasing each after the previous one lands. Squash-merging one PR flips every other PR touching the same file to DIRTY — even with no shared line — because their diffs used the now-changed line as unchanged context; that costs an `@dependabot rebase` round-trip per subsequent PR. This skill merges the first PR, then runs the `/alemax:dependabot-merge` rebase loop on each remaining PR before merging it. Works from any git repo with a GitHub remote.
license: MIT
compatibility: Requires `gh` (authenticated) + `git`. Declares `context: either`. Composes `alemax-dependabot-merge` (ship/understand that first). Merges multiple PRs (outward-facing); assumes the operator has accepted each bump in principle.
context: either
metadata:
  author: alemax
  version: "1.0"
---

## Wraps

No shell script. It's a serial driver over `/alemax:dependabot-merge`: merge the first PR, then for each subsequent PR run the full per-PR rebase-and-merge loop (because the prior merge staled it).

## The context-drift story

Two Dependabot PRs touching non-overlapping lines of the same file (e.g. #1 bumps `actions/checkout` and #2 bumps `astral-sh/setup-uv` in `.github/workflows/ci.yml`) do not actually conflict. But squash-merging #1 immediately flips #2 to `DIRTY`/`CONFLICTING`, because #2's diff referenced the line #1 changed as *unchanged context*. The unblock is another `@dependabot rebase` round-trip — and with N PRs that's N−1 extra cycles, purely from context drift. This skill automates the serial merge-then-rebase-next chain so the operator hands over a list of PR numbers once.

## When NOT to use this skill

- **A single Dependabot PR** — just use `/alemax:dependabot-merge <#>`.
- **PRs across different files** — they merge independently with no context drift; batching adds nothing (merge them individually or in any order).
- **You haven't reviewed the bumps** — this drives merge mechanics, not the accept/reject decision. Decide first, then batch.

## Steps

### Step 0 — Preflight + order

Parse the PR numbers from the argument (`/alemax:dependabot-merge-all 41 42 43` → `41 42 43`). If none given, offer to discover them:

```bash
gh pr list --author "app/dependabot" --state open --json number,title,mergeStateStatus \
  --jq '.[] | "#\(.number)  [\(.mergeStateStatus)]  \(.title)"'
```

Confirm the ordered list with the operator before acting. Merge order matters only in that each subsequent PR gets re-rebased; a sensible default is ascending PR number (oldest first).

### Step 1 — Safety-gate the whole set

For each PR, verify `author.login` is Dependabot (`app/dependabot` / `dependabot[bot]`) and `state == OPEN`. Refuse the batch if any PR is not a Dependabot PR — do not partially process a mixed set without the operator's say-so.

### Step 2 — Merge the first

Run the `alemax-dependabot-merge` flow on the first PR (short-circuit if already MERGEABLE, else rebase-loop then squash-merge `--delete-branch`). If it fails (timeout / real conflict / branch protection), **stop the batch** and report — do not cascade into the rest while the base is unresolved.

### Step 3 — For each subsequent PR: rebase-loop then merge

For every remaining PR in order, run the full `alemax-dependabot-merge` per-PR flow. The key is that this ALWAYS runs Steps 2–3 of the per-PR skill (comment `@dependabot rebase` + bounded poll) even if the PR briefly showed MERGEABLE earlier, because the previous merge just staled it. Concretely per PR:

1. `gh pr comment <#> --body "@dependabot rebase"` (the prior merge flipped it to DIRTY/UNKNOWN).
2. Poll `gh pr view <#> --json mergeStateStatus` every ~20s up to ~3 min until it leaves UNKNOWN/DIRTY and reaches CLEAN.
3. `gh pr merge <#> --squash --delete-branch`.

Announce progress per PR (`[2/3] #42 rebasing… merged abc1234`).

### Step 4 — Failure handling + final report

- **Stop on the first non-recoverable failure** (a real conflict a rebase won't fix, a branch-protection block, or a poll timeout) — do not keep merging past a broken link, since later PRs rebase onto whatever landed.
- Always end with a **state-of-all-PRs summary**: which merged (with SHAs), which is blocked and why, which were untouched. The operator resumes from there (fix the blocker, re-run with the remaining numbers).

## Edge cases

- **A subsequent PR auto-resolves without a rebase** — occasionally GitHub recomputes on its own and the PR is already CLEAN; the `@dependabot rebase` comment is then a harmless no-op and the merge proceeds immediately.
- **Dependabot supersedes a PR mid-batch** — if a PR closes (replaced by a newer bump), report it and continue with the remaining explicit numbers; don't chase the replacement automatically.
- **Rate-limiting** — many `@dependabot rebase` comments in quick succession can be throttled; if polls time out, the summary lets the operator re-run for the stragglers after a pause.

## Cross-links

- `.claude/skills/alemax-dependabot-merge/SKILL.md` — the per-PR primitive this composes; understand it first.
- `openspec/specs/alemax-dependabot-skills/spec.md` — the behavioral spec for both skills.
- `meta/docs/ALEMAX-SKILLS.md` — the `/alemax:*` family conventions.

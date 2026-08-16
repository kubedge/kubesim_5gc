---
name: alemax-reprioritise-ideas
description: Curate the § Suggested next-up section of `openspec/ideas.md` — walk § Raw ideas for `[ ]` entries, present the list with one-line summaries, let the operator pick 3–5 to surface as "next up", write pointer-only entries into § Suggested next-up. Operator-triggered, often before planning sessions. Does NOT touch § Archived ideas or § Raw ideas content.
license: MIT
compatibility: Requires bash, git, gh. Operates exclusively under `openspec/` (no macOS-system-rooted paths). Context-adaptive — in claude-meta it honors the canonical-only governance rule; in any other repo containing `openspec/ideas.md` it commits against that repo's own origin.
context: either
metadata:
  author: alemax
  version: "1.0"
---

## Wraps

No single shell script. The workflow is: walk `openspec/ideas.md` § Raw ideas, present `[ ]` entries with one-line summaries, let the operator pick a small set to surface as "next up", write pointer-only entries into § Suggested next-up.

The skill embodies the optional curation step in the rhythm-based ideas.md lifecycle (per `openspec/specs/spec-governance/spec.md`). § Suggested next-up is allowed to be empty; this skill is the workflow for populating it when an operator wants to.

## The reprioritisation story

§ Raw ideas can have 30+ `[ ]` entries at any given time. The operator picking the next thing to work on benefits from a small curated set surfaced at the top of `ideas.md` — § Suggested next-up. This skill is the curation workflow.

Each surfaced entry is a **pointer**, not a copy:
- Pointer format: `- <slug> — <one-line summary>`
- The full body stays in § Raw ideas (the operator scrolls down to read it when ready).
- This avoids duplication and keeps § Suggested next-up small.

Each run **replaces** § Suggested next-up (does not append). The operator who runs the skill is deciding "what's next up RIGHT NOW", not adding to a growing list.

## Behavior overview

1. **Preflight.** Detect context (claude-meta vs any other repo); verify `openspec/ideas.md` exists; clean working tree. `context: either` — no meta-vs-project refusal.
2. **Walk § Raw ideas.** Extract every `[ ]` entry's slug + one-line summary.
3. **Present + pick.** Show the numbered list; operator picks 3–5 by index or slug.
4. **Detect existing § Suggested next-up.** If non-empty, ask "Replace, add to, or skip?"
5. **Write.** Replace (or append-to) the § Suggested next-up section. Atomic file write.
6. **Branch + commit (+ PR in claude-meta).** Two-mode, keyed on context.
7. **Final summary.**

## Steps

### Step 1 — Preflight (Context detect + ideas.md presence + clean tree)

This skill declares `context: either`. It does NOT refuse on the meta-vs-project
distinction; it detects the context (to pick the commit/PR flow later) and refuses
only when there is no `openspec/ideas.md` to curate.

```bash
# Context detect — meta-repo vs any other repo (used later to pick commit/PR flow).
CURRENT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ "$ORIGIN_URL" == *"claude-meta"* && "$CURRENT_ROOT" == *"/claude-meta" ]]; then
  CURRENT_CONTEXT="claude-meta"
else
  CURRENT_CONTEXT="project"
fi
REPO_ROOT="$CURRENT_ROOT"

# Refusal gate — there must be an openspec/ideas.md to curate.
if [[ ! -f "$REPO_ROOT/openspec/ideas.md" ]]; then
  echo "ERROR: alemax-reprioritise-ideas found no openspec/ideas.md at the repo root." >&2
  echo "  repo: $REPO_ROOT" >&2
  echo "" >&2
  echo "This skill curates a repo's own openspec/ideas.md § Suggested next-up. Run it" >&2
  echo "from the meta-repo or from a bootstrapped project (both ship openspec/ideas.md)." >&2
  exit 1
fi

# Clean tree check
if ! git diff-index --quiet HEAD --; then
  echo "ERROR: working tree dirty — commit or stash first" >&2
  exit 1
fi
```

`REPO_ROOT` replaces the old `META_ROOT`; subsequent steps operate on the current
repo's own `openspec/ideas.md`, whether that repo is claude-meta or a project.

### Step 2 — Walk § Raw ideas

Extract `[ ]` entries between `## Raw ideas` and end-of-file:

```bash
awk '
  /^## Raw ideas$/ { in_raw=1; next }
  /^## / { in_raw=0 }
  in_raw && /^- \[ \]/ { print }
' openspec/ideas.md
```

For each `[ ]` line, extract:
- **Slug**: the backtick-wrapped name at the end of the bold title (e.g., from `**foo (`bar-slug`).**` extract `bar-slug`). If no slug pattern, use a short ID derived from the first 30 chars of the title.
- **One-line summary**: the title text (between `**` and `.**`).

### Step 3 — Present + pick

```
Active backlog (§ Raw ideas, 30 entries):

   1. host-isolation-remediation-jbrette  — TODO (operator, one-shot): host-isolation remediation for jbrette
   2. migrate-existing-operator-host-isolation  — Document the "migrate-existing-operator" procedure
   3. enforce-host-isolation-in-meta  — Enforce host-isolation in meta-repo via pre-commit hook
   ...
  30. alemax-reprioritise-ideas-skill  — /alemax:reprioritise-ideas — § Suggested next-up maintenance

Pick 3–5 to surface in § Suggested next-up [comma-separated indices or slugs, blank to skip]:
```

Accept indices, slugs, or both (e.g., `2, 5, dot-local-scratch-convention`).

Validate every input matches a real entry; reject invalid with "Unknown slug: <slug>" and re-prompt.

### Step 4 — Detect existing § Suggested next-up

```bash
EXISTING=$(awk '
  /^## Suggested next-up$/ { in_su=1; next }
  /^## / { in_su=0 }
  in_su && /^- / { print }
' openspec/ideas.md)
```

If `$EXISTING` is non-empty, ask:
```
§ Suggested next-up currently contains:
  - foo — Foo idea description
  - bar — Bar idea description

[r]eplace, [a]dd to, or [s]kip?
```

`r` (default): replace existing entries.
`a`: append new entries below existing.
`s`: exit without mutation.

### Step 5 — Write

Build the mutated `openspec/ideas.md` in a tempfile. The § Suggested next-up section between its `## Suggested next-up` heading and the next `## Raw ideas` heading is rewritten to:

```markdown
## Suggested next-up

*Optional operator-curated short list of raw ideas being prioritized. Empty is fine — populated by the operator when planning the next implementation cycle.*

- slug-1 — one-line summary
- slug-2 — one-line summary
- ...

```

(The italic intro line stays; the bullets are replaced.)

Atomic write:
```bash
TMPFILE="$(mktemp)"
# build mutated content
mv "$TMPFILE" openspec/ideas.md
```

### Step 6 — Branch + commit (+ PR in claude-meta)

Two-mode, keyed on `$CURRENT_CONTEXT` from Step 1.

```bash
BRANCH="chore/reprioritise-ideas-$(date +%Y-%m-%d)"
git checkout -b "$BRANCH"
git add openspec/ideas.md
git commit -m "chore(openspec): reprioritise § Suggested next-up"
git push -u origin "$BRANCH"

if [[ "$CURRENT_CONTEXT" == "claude-meta" ]]; then
  # Meta-repo: openspec/ideas.md is canonical-only — land via PR to canonical.
  gh pr create --base main --title "chore(openspec): reprioritise § Suggested next-up" --body "..."
else
  # Project: the repo owns its openspec/ideas.md. The branch is pushed to the
  # project's own origin; the operator merges it (or opens a PR to their own
  # main) per the project's own workflow. No upstream / canonical-only rule.
  echo "Pushed $BRANCH to origin. Merge it into your main (or open a PR on your own repo)."
fi
```

### Step 7 — Final summary

```
Reprioritisation complete.
  Surfaced:  3 entries
  Mode:      replace (was: 2 entries)
  Landed:    PR to canonical (claude-meta)  |  branch pushed to origin (project)
```

## Edge cases

- **Zero `[ ]` entries** → skill reports "No active backlog to reprioritise" and exits.
- **Operator picks zero** → no mutation; exit cleanly.
- **Operator picks >10** → skill warns "§ Suggested next-up is meant to be small (target 3–5; max 10). Proceed with N entries? [y/n]".
- **Operator picks invalid slug** → re-prompt with the validation message until all inputs are valid.
- **Existing § Suggested next-up contains entries that are now `[x]` (got archived)** → on `replace`, they're cleared. On `add`, the operator is shown them and asked whether to keep or drop each.

## system-path-rule

This skill operates exclusively under `openspec/`. No macOS-system-rooted paths involved. The convention is referenced for forward-compatibility.

## Cross-links

- `openspec/specs/spec-governance/spec.md` — the rhythm-based ideas.md structure this skill operates on (§ Suggested next-up is the optional curated section).
- `openspec/specs/alemax-skills/spec.md` — family conventions.
- `.claude/skills/alemax-archive-ideas/SKILL.md` — sibling skill for § Archived ideas — by capability reshape.

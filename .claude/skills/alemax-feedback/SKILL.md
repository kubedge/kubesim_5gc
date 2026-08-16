---
name: alemax-feedback
description: Lightweight per-repo feedback capture. Appends a structured row to `.local/feedback.md` at the current repo's root — works from any claude-meta-managed repo (meta-repo or project clone). Conversationally prompts for context + finding + severity tag; appends in 5 seconds; never breaks operator flow. Output format is stable enough for a future `/alemax:collect-feedback` skill to parse.
license: MIT
compatibility: Requires bash, git. Honors `dot-local-scratch-convention` (`.local/` gitignored). The first `/alemax:*` skill with `context: either` — works from meta-repo OR project clones.
context: either
metadata:
  author: alemax
  version: "1.0"
---

## Wraps

No single shell script. The workflow is: prompt the operator conversationally for 2-3 fields, append a structured row to `.local/feedback.md` at the current repo's root, confirm.

This skill is the simplest piece of the `alemax-feedback-and-diagnose-skills` cluster. It captures friction/bugs/ideas mid-session so the operator never breaks flow to open `.local/feedback.md` directly. A future `/alemax:collect-feedback` skill (separate change) will walk operators' projects, read these files, dedupe against shipped fixes, and emit a canonical PR.

## The feedback story

Operators encounter friction mid-session: a missing scaffolding feature, a harness quirk, a bug in a generated file, an idea that just popped up. Today they either (a) interrupt their flow to add an `[ ]` entry to `openspec/ideas.md` (heavy ceremony for one thought), (b) write it down somewhere unstructured ("notes.md", `TODO.md`), or (c) forget by end-of-session.

`/alemax:feedback` is the lightweight option — 5 seconds, 3 prompts, done. The structured row lands in `.local/feedback.md` (gitignored per `dot-local-scratch-convention`), accumulates over time, and gets harvested by `/alemax:collect-feedback` when the operator wants to batch-promote findings into the backlog.

## Behavior overview

1. **Step 0 — Context check.** Detect meta-repo vs project (per `alemax-skills-context-awareness`). Don't refuse (this skill declares `context: either`). Branch only on which repo's `.local/feedback.md` to write to (always the current repo).
2. **Step 1 — Prompt for Context** (what the operator was doing). One free-form line.
3. **Step 2 — Prompt for Finding** (the friction / bug / idea). 1-3 sentences free-form.
4. **Step 3 — Prompt for Severity** with 4 valid tags: `blocker` / `friction` / `idea` / `harness`. Reject + re-prompt on invalid.
5. **Step 4 — Optional Related diagnosis link.** Skill asks "Any related diagnosis path? [skip / path]". On skip, omit the field. On path, include `**Related diagnosis:** <path>`.
6. **Step 5 — Build the row + append.** Use atomic tempfile + `mv` (consistent with the family pattern). Create `.local/feedback.md` if missing.
7. **Step 6 — Confirm to operator** with a summary of what was appended + the file path.

## Steps

### Step 0 — Context check (passes through)

```bash
CURRENT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ "$ORIGIN_URL" == *"claude-meta"* && "$CURRENT_ROOT" == *"/claude-meta" ]]; then
  CURRENT_CONTEXT="claude-meta"
else
  CURRENT_CONTEXT="project"
fi
# Skill declares context: either — no refusal. Both contexts proceed.
FEEDBACK_FILE="$CURRENT_ROOT/.local/feedback.md"
```

### Step 1 — Prompt for Context

```
What were you doing when this came up? (one line)
```

Capture free-form input as `$CONTEXT`.

### Step 2 — Prompt for Finding

```
What's the friction / bug / idea / observation? (1-3 sentences)
```

Capture free-form input as `$FINDING`.

### Step 3 — Prompt for Severity (validated)

```
Severity? [blocker / friction / idea / harness]
```

Validate input matches exactly one of the 4 tags. On mismatch:

```
Invalid. Use one of: blocker / friction / idea / harness
```

…and re-prompt until valid.

### Step 4 — Optional Related diagnosis

```
Related diagnosis path? (e.g. .local/diagnosis/foo/ or openspec/diagnosis/2026-06-01-foo/) [skip to omit]
```

If `skip` or blank, omit. Else capture as `$RELATED_DIAGNOSIS`.

### Step 5 — Build and append

```bash
mkdir -p "$CURRENT_ROOT/.local"
TIMESTAMP="$(date +%Y-%m-%d\ %H:%M)"

# Build row in a tempfile
TMPFILE="$(mktemp)"
{
  if [ -s "$FEEDBACK_FILE" ]; then
    cat "$FEEDBACK_FILE"
    printf '\n'
  fi
  printf '### %s — %s\n\n' "$TIMESTAMP" "$SEVERITY"
  printf '**Context:** %s\n' "$CONTEXT"
  printf '**Finding:** %s\n' "$FINDING"
  if [ -n "${RELATED_DIAGNOSIS:-}" ]; then
    printf '**Related diagnosis:** %s\n' "$RELATED_DIAGNOSIS"
  fi
} > "$TMPFILE"
mv "$TMPFILE" "$FEEDBACK_FILE"
```

### Step 6 — Confirm

```
Captured.
  File:     <repo>/.local/feedback.md
  Tag:      <severity>
  Context:  <context>
  Finding:  <finding>
```

## Edge cases

- **`.local/` doesn't exist** — the `mkdir -p` in Step 5 handles it.
- **`.local/feedback.md` doesn't exist** — the tempfile builds from empty + the new row; the `mv` creates the file.
- **Operator types Ctrl-C mid-prompt** — no mutation has happened yet (the build-and-append is the final step). Skill exits cleanly.
- **Operator submits the same finding twice within minutes** — both rows land in the file; the operator hand-cleans if needed. (Auto-dedup is the collector skill's job.)

## system-path-rule

This skill operates exclusively under the current repo's `.local/`. No macOS-system-rooted paths involved.

## Cross-links

- `openspec/specs/spec-governance/spec.md` — `.local/` convention from `dot-local-scratch-convention` (archived 2026-06-01).
- `openspec/specs/alemax-skills/spec.md` — family conventions + `context: either` declaration requirement from `alemax-skills-context-awareness` (archived 2026-06-01).
- `.claude/skills/alemax-diagnose/SKILL.md` — sibling skill that writes diagnosis docs; the optional `**Related diagnosis:**` field in feedback rows can link to a diagnosis directory.
- Future `alemax-collect-feedback-skill` (captured as follow-up idea) — the collector that parses these rows.

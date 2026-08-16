---
name: alemax-front-burner
description: Operator-triggered "I'm picking up where I left off" skill. Walks four phases — (1) read `.local/resume.md` and parse `schema_version`, (2) drift detection (local-cheap always; remote-expensive opt-in via `--check-remote` and `--check-openspec`), (3) surface findings in scannable order with staleness warnings, (4) propose next step. Strictly read-only on the working repo and `.local/resume.md`. Never executes the proposed action. Pairs with `/alemax:back-burner` (producer) which writes the checkpoint.
license: MIT
compatibility: Requires bash, git. Optional `gh` for `--check-openspec`. Honors `dot-local-scratch-convention` (`.local/` gitignored). Declares `context: either` — works from meta-repo OR project clones.
context: either
metadata:
  author: alemax
  version: "1.0"
---

## Wraps

No single shell script. The workflow is: walk the operator through four phases of session resume using prompts + git inspection + (optionally) `gh pr list`. The skill is strictly read-only — the only side effects permitted are `git fetch --no-write-fetch-head` (opt-in via `--check-remote`) and `gh pr list` (opt-in via `--check-openspec`).

This skill is the **consumer side** of the back-burner/front-burner session-management pair. It reads `.local/resume.md` written by `/alemax:back-burner` (canonical schema in `openspec/specs/back-burner-session-wind-down/spec.md`). The schema is the asymmetric contract: producer evolves; consumer adapts via schema-version routing.

## The resume story

Operators open fresh Claude sessions and have to reconstruct "where was I?" from `git log`, transcripts, and memory. `/alemax:front-burner` is the dedicated resume skill: four phases that lift the operator's prior context out of `.local/resume.md` (if the back-burner skill ran last session) or synthesize it from `git merge-base HEAD origin/main` (if not), then propose a concrete next step. Net effect: zero-friction session re-entry.

The skill is **propose, never execute**. The proposal is text; the operator runs the next step themselves in the next conversation turn. Coupling to the producer is loose: the skill works even if no back-burner has ever run in this clone — standalone mode covers that.

## Behavior overview

0. **Step 0 — Context check.** Detect meta-repo vs project. Don't refuse (this skill declares `context: either`). Branch only on which repo's `.local/` to read from (always the current repo).
1. **Phase 1 — Read checkpoint.** Parse `.local/resume.md` frontmatter `schema_version`; route to v1-canonical / v2+-best-effort / malformed-degraded / standalone-mode. Build internal state object.
2. **Phase 2 — Drift detection.** Local-cheap: branch, HEAD, working-tree, stash. Remote-expensive (opt-in): origin/main advance, new openspec changes, open PRs.
3. **Phase 3 — Surface findings.** Fixed scannable order; staleness warning prepended; one terminal line per finding.
4. **Phase 4 — Propose, never execute.** Three options; skill terminates after operator selects.

## Steps

### Step 0 — Context check (passes through)

```bash
CURRENT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$CURRENT_ROOT" ]; then
  echo "Error: not inside a git repository — /alemax:front-burner requires a repo root for .local/resume.md lookup"
  exit 1
fi
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ "$ORIGIN_URL" == *"claude-meta"* && "$CURRENT_ROOT" == *"/claude-meta" ]]; then
  CURRENT_CONTEXT="claude-meta"
else
  CURRENT_CONTEXT="project"
fi
# Skill declares context: either — no refusal.
RESUME_FILE="$CURRENT_ROOT/.local/resume.md"
CHECK_REMOTE="${CHECK_REMOTE:-0}"     # set to 1 if --check-remote passed
CHECK_OPENSPEC="${CHECK_OPENSPEC:-0}" # set to 1 if --check-openspec passed
```

Parse `--check-remote` and `--check-openspec` from skill args; set the corresponding env vars to `1`.

### Phase 1 — Read checkpoint

**1a — File present? Route to standalone if not.**

```bash
if [ ! -f "$RESUME_FILE" ]; then
  echo "No checkpoint found — synthesizing from git history"
  MODE="standalone"
  SNAPSHOT_HEAD_SHA="$(git merge-base HEAD origin/main 2>/dev/null || git rev-parse HEAD)"
  SNAPSHOT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse HEAD)"
  SNAPSHOT_RECORDED_AT=""  # no recorded time in synthetic mode
  RECORDED_NEXT_STEP=""
  RECORDED_OPEN_QUESTIONS=""
  RECORDED_RECENT_ACTIVITY="$(git log --oneline -5 2>/dev/null | sed 's/^/  /')"
fi
```

**1b — File present: parse frontmatter `schema_version`.**

```bash
if [ -f "$RESUME_FILE" ]; then
  # Extract YAML frontmatter (between first and second --- lines)
  FRONTMATTER="$(awk '/^---$/{c++; next} c==1' "$RESUME_FILE")"
  if [ -z "$FRONTMATTER" ]; then
    echo "Warning: .local/resume.md has no parseable YAML frontmatter — treating as malformed"
    MODE="malformed"
  else
    SCHEMA_VERSION="$(echo "$FRONTMATTER" | grep '^schema_version:' | awk '{print $2}')"
    case "$SCHEMA_VERSION" in
      1)
        MODE="v1"
        ;;
      ''|*[!0-9]*)
        echo "Warning: schema_version is missing or non-integer — treating as malformed"
        MODE="malformed"
        ;;
      *)
        if [ "$SCHEMA_VERSION" -ge 2 ]; then
          echo "Warning: checkpoint was written by a newer back-burner schema version $SCHEMA_VERSION; reading best-effort"
          MODE="future"
        fi
        ;;
    esac
  fi
fi
```

**1c — Extract v1-known fields (works for v1 and future modes; ignored in malformed/standalone).**

```bash
if [ "$MODE" = "v1" ] || [ "$MODE" = "future" ]; then
  SNAPSHOT_RECORDED_AT="$(echo "$FRONTMATTER" | grep '^recorded_at:' | sed 's/^recorded_at: *//')"
  SNAPSHOT_BRANCH="$(echo "$FRONTMATTER" | grep '^branch:' | sed 's/^branch: *//')"
  SNAPSHOT_HEAD_SHA="$(echo "$FRONTMATTER" | grep '^head_sha:' | sed 's/^head_sha: *//')"
  SNAPSHOT_WORKING_TREE_CLEAN="$(echo "$FRONTMATTER" | grep '^working_tree_clean:' | awk '{print $2}')"

  # Extract body sections (between ## headings)
  RECORDED_NEXT_STEP="$(awk '/^## Next step$/{f=1;next} /^## /{f=0} f' "$RESUME_FILE")"
  RECORDED_OPEN_QUESTIONS="$(awk '/^## Open questions$/{f=1;next} /^## /{f=0} f' "$RESUME_FILE")"
  RECORDED_RECENT_ACTIVITY="$(awk '/^## Recent activity$/{f=1;next} /^## /{f=0} f' "$RESUME_FILE")"
fi

if [ "$MODE" = "malformed" ]; then
  # Treat whole file as opaque body; use synthetic snapshot
  SNAPSHOT_HEAD_SHA="$(git merge-base HEAD origin/main 2>/dev/null || git rev-parse HEAD)"
  SNAPSHOT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null)"
  SNAPSHOT_RECORDED_AT=""
fi
```

### Phase 2 — Drift detection

**2a — Local-cheap signals (always run).**

```bash
CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null)"
CURRENT_HEAD_SHA="$(git rev-parse HEAD)"

# Branch drift
DRIFT_BRANCH=""
if [ -n "$SNAPSHOT_BRANCH" ] && [ "$CURRENT_BRANCH" != "$SNAPSHOT_BRANCH" ]; then
  DRIFT_BRANCH="$SNAPSHOT_BRANCH → $CURRENT_BRANCH"
fi

# HEAD drift
DRIFT_HEAD=""
if [ -n "$SNAPSHOT_HEAD_SHA" ] && [ "$CURRENT_HEAD_SHA" != "$SNAPSHOT_HEAD_SHA" ]; then
  DRIFT_HEAD_COUNT="$(git rev-list "$SNAPSHOT_HEAD_SHA..HEAD" --count 2>/dev/null || echo "?")"
  DRIFT_HEAD_FIRST3="$(git log "$SNAPSHOT_HEAD_SHA..HEAD" --oneline 2>/dev/null | head -3)"
  DRIFT_HEAD="$DRIFT_HEAD_COUNT commits since checkpoint"
fi

# Working-tree drift
DRIFT_WT_UNSTAGED="$(git status --porcelain 2>/dev/null | grep -E '^.M' | wc -l | tr -d ' ')"
DRIFT_WT_STAGED="$(git status --porcelain 2>/dev/null | grep -E '^[MAD] ' | wc -l | tr -d ' ')"
DRIFT_WT_UNTRACKED="$(git status --porcelain 2>/dev/null | grep -E '^\?\?' | wc -l | tr -d ' ')"

# Stash drift (new since recorded snapshot)
DRIFT_STASH=""
if [ -n "$SNAPSHOT_RECORDED_AT" ]; then
  RECORDED_EPOCH="$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$SNAPSHOT_RECORDED_AT" +%s 2>/dev/null || echo 0)"
  DRIFT_STASH="$(git stash list --pretty='%gd %ci %s' 2>/dev/null | while read -r ref date_iso _z msg; do
    stash_epoch=$(date -j -f '%Y-%m-%d %H:%M:%S' "$date_iso" +%s 2>/dev/null || echo 0)
    [ "$stash_epoch" -ge "$RECORDED_EPOCH" ] && echo "  $ref $msg"
  done)"
fi
```

**2b — Remote-expensive signals (opt-in).**

```bash
DRIFT_REMOTE=""
if [ "$CHECK_REMOTE" = "1" ]; then
  git fetch --no-write-fetch-head origin main >/dev/null 2>&1
  if [ -n "$SNAPSHOT_HEAD_SHA" ]; then
    REMOTE_COUNT="$(git rev-list "$SNAPSHOT_HEAD_SHA..origin/main" --count 2>/dev/null || echo "?")"
    REMOTE_FIRST3="$(git log "$SNAPSHOT_HEAD_SHA..origin/main" --oneline 2>/dev/null | head -3)"
    [ "$REMOTE_COUNT" -gt 0 ] && DRIFT_REMOTE="$REMOTE_COUNT commits on origin/main since checkpoint"
  fi
fi

DRIFT_OPENSPEC=""
if [ "$CHECK_OPENSPEC" = "1" ]; then
  NEW_CHANGES_COUNT=0
  if [ -n "$SNAPSHOT_RECORDED_AT" ] && [ -d openspec/changes ]; then
    RECORDED_EPOCH="$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$SNAPSHOT_RECORDED_AT" +%s 2>/dev/null || echo 0)"
    NEW_CHANGES_COUNT="$(find openspec/changes -maxdepth 1 -mindepth 1 -type d -newermt "@$RECORDED_EPOCH" 2>/dev/null | wc -l | tr -d ' ')"
  fi
  OPEN_PRS="$(gh pr list --state open --base main --json number,title --limit 20 2>/dev/null | jq -r '.[] | "  #\(.number) \(.title)"' | head -3)"
  DRIFT_OPENSPEC="${NEW_CHANGES_COUNT} new openspec changes; $(echo "$OPEN_PRS" | wc -l | tr -d ' ') open PRs"
fi
```

### Phase 3 — Surface findings

**3a — Staleness warning (prepended).**

```bash
STALENESS=""
if [ -n "$SNAPSHOT_RECORDED_AT" ]; then
  NOW_EPOCH="$(date +%s)"
  RECORDED_EPOCH="$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$SNAPSHOT_RECORDED_AT" +%s 2>/dev/null || echo "$NOW_EPOCH")"
  AGE_HOURS=$(( (NOW_EPOCH - RECORDED_EPOCH) / 3600 ))
  AGE_DAYS=$(( AGE_HOURS / 24 ))
  if [ "$AGE_DAYS" -gt 7 ]; then
    STALENESS="⚠ checkpoint is $AGE_DAYS days old — consider discarding and using standalone mode"
  elif [ "$AGE_HOURS" -gt 24 ]; then
    STALENESS="checkpoint is $AGE_HOURS hours old — verify it still reflects current intent"
  fi
fi
```

**3b — Mode caveats (prepended after staleness).**

- `standalone`: print "synthetic snapshot — no recorded next step or open questions"
- `malformed`: print "checkpoint is malformed — reading body as opaque text"
- `future`: print "checkpoint schema version > 1 — read best-effort, some fields may be missing"

**3c — Emit findings in fixed order.**

```
[staleness warning if any]
[mode caveat if any]

## Next step (recorded)
<first line of RECORDED_NEXT_STEP> [expand if multi-line]

## Open questions
<first 3 bullets> [expand if more]

## Drift
  branch:        <DRIFT_BRANCH or "—">
  HEAD:          <DRIFT_HEAD or "—">
  working tree:  <unstaged>U <staged>S <untracked>?
  stash:         <DRIFT_STASH or "—">
  remote:        <DRIFT_REMOTE or "—" or "(not checked — pass --check-remote)">
  openspec:      <DRIFT_OPENSPEC or "—" or "(not checked — pass --check-openspec)">
```

Multi-line content is collapsed to first line + `[expand]` cue.

### Phase 4 — Propose, never execute

**4a — Determine recommended next-action.**

- If `MODE` ∈ {`v1`, `future`} AND `RECORDED_NEXT_STEP` non-empty → option (a) = first line of `RECORDED_NEXT_STEP`.
- If `MODE` ∈ {`standalone`, `malformed`} → option (a) = best-effort recommendation based on top drift signal (e.g., "you have unstaged work in `<file>`; consider committing or stashing before starting new work").

**4b — Canonical-only governance reminder.**

```bash
CANONICAL_ONLY_RE='openspec/(changes/|specs/|decisions\.md|ideas\.md|\.openspec\.yaml)'
FORK_MAIN=0
[[ "$CURRENT_BRANCH" == "main" && "$ORIGIN_URL" != *"alemaxdesign/claude-meta"* ]] && FORK_MAIN=1

GOVERNANCE_REMINDER=""
if [ "$FORK_MAIN" = "1" ] && echo "$RECORDED_NEXT_STEP" | grep -qE "$CANONICAL_ONLY_RE"; then
  GOVERNANCE_REMINDER=" (note: would mutate canonical-only path — switch to feature branch first)"
fi
```

**4c — Present options via AskUserQuestion (or text-prompt fallback).**

```
Phase 4 — propose next step:
  (a) <recommended next step>${GOVERNANCE_REMINDER}
  (b) Address top drift signal: <top drift summary>
  (c) Something else
```

**4d — On selection, print the selected option's text and terminate.**

The skill SHALL NOT execute the selected option. It SHALL NOT invoke any slash command, run any git command beyond the read-only inspections above, or write any file. The operator runs the proposed action manually in a subsequent conversation turn.

## Edge cases

- **`.local/resume.md` exists but is empty** — phase 1 treats as malformed; mode caveat surfaces.
- **`origin/main` does not exist (no remote tracking)** — phase 2 standalone-mode `merge-base` falls back to `git rev-parse HEAD`; remote drift check is silently skipped with a one-line note.
- **`gh` is not authenticated for `--check-openspec`** — phase 2 prints a warning and continues; openspec drift surfaces as "(gh auth not available)".
- **Operator passes both `--check-remote` and `--check-openspec` in an offline environment** — `git fetch` and `gh pr list` will fail loudly; the skill catches, prints a warning per signal, and continues with local-only.
- **Operator selects option (c) "something else"** — the skill prints "no recommendation selected; you decide the next step" and terminates.

## Read-only invariant

The skill's permitted side effects, in totality:
1. `git fetch --no-write-fetch-head origin main` — opt-in via `--check-remote`.
2. `gh pr list --state open --base main` — opt-in via `--check-openspec`.

Nothing else. No `git commit`, no `git stash`, no `git checkout`, no `git reset`, no file writes (not to `.local/resume.md`, not to any tracked file, not to settings.json). This is verified by code audit per `tasks.md` § 7.

## system-path-rule

This skill operates exclusively under the current repo's `.local/` (for reading `resume.md`), the current repo's git state, and optionally `gh` API endpoints. No macOS-system-rooted paths touched.

## Cross-links

- `openspec/specs/front-burner-session-resume/spec.md` — this skill's canonical behavioral spec (created at archive time).
- `openspec/specs/back-burner-session-wind-down/spec.md` — `.local/resume.md` schema canonical source.
- `openspec/specs/spec-governance/spec.md` — `.local/` convention from `dot-local-scratch-convention` (archived 2026-06-01).
- `openspec/specs/alemax-skills/spec.md` — family conventions + `context: either` declaration requirement.
- `.claude/skills/alemax-back-burner/SKILL.md` — paired producer skill that writes `.local/resume.md` at session end.
- `meta/docs/ALEMAX-SKILLS.md` — family roster.

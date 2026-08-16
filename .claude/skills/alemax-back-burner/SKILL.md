---
name: alemax-back-burner
description: Operator-triggered end-of-session housekeeping. Walks a five-phase wind-down — (1) checkpoint draft to `.local/resume.md`, (2) `/tmp/claude-*` cleanup, (3) `.claude/settings.json` + `.claude/settings.local.json` sanity-pass (read-only), (4) working-tree audit (advisory, four options per item), (5) handoff prompt instructing the operator to `/compact` + `/quit`. Read-only on both settings files. Never auto-invokes `/compact` or `/quit`. Pairs with `/alemax:front-burner` (consumer) which reads `.local/resume.md` on next session start.
license: MIT
compatibility: Requires bash, git. Honors `dot-local-scratch-convention` (`.local/` gitignored). Declares `context: either` — works from meta-repo OR project clones.
context: either
metadata:
  author: alemax
  version: "1.0"
---

## Wraps

No single shell script. The workflow is: walk the operator through five phases of end-of-session housekeeping using prompts + small per-phase shell snippets. The only persistent artifact is `.local/resume.md`; everything else is operator-confirmed mutations to the current state.

This skill is the **producer side** of the back-burner/front-burner session-management pair. It writes `.local/resume.md` for the paired `/alemax:front-burner` skill to consume on the next session start. The schema is canonical (defined in `openspec/specs/back-burner-session-wind-down/spec.md`) so the asymmetric producer/consumer contract is stable.

## The wind-down story

Operators wrap up Claude sessions with no consistent ritual: they decide ad-hoc what to commit before `/quit`, /tmp scratch accumulates session-over-session, per-project `.claude/settings.json` collects session-scoped overrides that should not persist, and the "where was I?" state at session start has to be reconstructed from `git log` + memory. `/alemax:back-burner` is the dedicated wind-down skill: a five-phase walkthrough that produces a structured checkpoint and leaves the working state ready for clean resume.

The five phases fall into two categories:
- **State preservation** (1, 4): things the next session needs to pick up — the checkpoint file and the explicit handling of in-flight work.
- **Session-private hygiene** (2, 3): clutter that should not survive the session — `/tmp` scratch and session-scoped settings.

Phase 5 is the punctuation: a prompt reminding the operator to `/compact` + `/quit` themselves. The skill **never auto-invokes either**.

## Behavior overview

0. **Step 0 — Context check.** Detect meta-repo vs project (per `alemax-skills-context-awareness`). Don't refuse (this skill declares `context: either`). Branch only on which repo's `.local/` to write to (always the current repo).
1. **Phase 1 — Checkpoint draft.** `.gitignore` precondition check → prompt for "Next step" prose → write `.local/resume.md` with versioned YAML frontmatter + canonical H2 body sections.
2. **Phase 2 — /tmp cleanup.** Enumerate `/tmp/claude-*` files newer than the session floor; per-candidate confirm; respect the prefix restriction (no other paths touched).
3. **Phase 3 — Settings sanity-pass.** Read both `.claude/settings.json` AND `.claude/settings.local.json` (operator-local file accumulates session-scoped `permissions.allow` adds — Claude Code writes there, not to the checked-in file). Emit per-file header; report candidate session-scoped overrides with three sharpened heuristics (absolute `/Volumes/AIML0NN/...` paths / long literal arg strings / literal full commands with no glob metacharacters); record any operator-requested reverts in `.local/resume.md § Open questions`. **READ-ONLY**.
4. **Phase 4 — Working-tree audit (advisory).** Surface unstaged/staged/untracked/new-stashes. Per-item four options. Canonical-only guard refuses commit-now for `openspec/**` on fork main.
5. **Phase 5 — Handoff prompt.** Print exact text + exit. Never auto-invokes `/compact` or `/quit`.

## Steps

### Step 0 — Context check (passes through)

```bash
CURRENT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$CURRENT_ROOT" ]; then
  echo "Error: not inside a git repository — /alemax:back-burner requires a repo root for .local/resume.md placement"
  exit 1
fi
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ "$ORIGIN_URL" == *"claude-meta"* && "$CURRENT_ROOT" == *"/claude-meta" ]]; then
  CURRENT_CONTEXT="claude-meta"
else
  CURRENT_CONTEXT="project"
fi
# Skill declares context: either — no refusal. Both contexts proceed.
RESUME_FILE="$CURRENT_ROOT/.local/resume.md"
SESSION_FLOOR="$(date -j -f '%Y-%m-%d %H:%M:%S' "$(date +%Y-%m-%d) 00:00:00" +%s 2>/dev/null || date -d 'today 00:00' +%s)"
DRY_RUN="${DRY_RUN:-0}"  # set to 1 if --dry-run passed
```

Parse `--dry-run` from skill args. If present, set `DRY_RUN=1`; every phase below treats writes/mutations as no-ops + describes-only.

### Phase 1 — Checkpoint draft

**1a — `.gitignore` precondition check.**

```bash
gitignore_has_local() {
  local root="$1"
  # Look for `.local/` (anchored or unanchored) in any .gitignore from root up
  if [ -f "$root/.gitignore" ] && grep -qE '^\.?/?\.local/?$' "$root/.gitignore"; then
    return 0
  fi
  return 1
}
```

If `gitignore_has_local "$CURRENT_ROOT"` returns false, prompt:

```
.gitignore does not exclude .local/. The checkpoint file would be visible to git.
Add a `.local/` rule to .gitignore now? [y/n]
```

- On **y**: append `.local/` to `$CURRENT_ROOT/.gitignore` (unless `DRY_RUN=1`). Note that the gitignore edit itself is uncommitted; it will be surfaced in phase 4 as a candidate change.
- On **n**: print warning and SKIP phase 1 entirely (do not write `.local/resume.md`). Continue to phase 2.

**1b — Gather frontmatter fields.**

```bash
BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse HEAD)"
HEAD_SHA="$(git rev-parse HEAD)"
RECORDED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# working_tree_clean is filled after phase 4 (in-place update)
```

**1c — Prompt for "Next step" prose.**

```
What's the next step when you resume? (one line or more — what's the next thing you'd act on)
```

Capture as `$NEXT_STEP`. Refuse to proceed past phase 1 with empty input (re-prompt once; if still empty, treat as "(no next step recorded)" and continue).

**1d — Pre-populate `## Recent activity`.**

```bash
RECENT_ACTIVITY="$(git log --oneline -5 2>/dev/null | sed 's/^/- /')"
```

**1e — Write `.local/resume.md` atomically.**

```bash
mkdir -p "$CURRENT_ROOT/.local"
TMPFILE="$(mktemp)"
{
  printf -- '---\n'
  printf 'schema_version: 1\n'
  printf 'recorded_at: %s\n' "$RECORDED_AT"
  printf 'branch: %s\n' "$BRANCH"
  printf 'head_sha: %s\n' "$HEAD_SHA"
  printf 'working_tree_clean: false\n'  # updated post-phase-4
  printf -- '---\n'
  printf '\n'
  printf '## Next step\n\n%s\n\n' "$NEXT_STEP"
  printf '## Open questions\n\n'  # populated by phases 3, 4
  printf '\n'
  printf '## Recent activity\n\n%s\n' "$RECENT_ACTIVITY"
} > "$TMPFILE"
[ "$DRY_RUN" = "1" ] && rm -f "$TMPFILE" && echo "[dry-run] would write $RESUME_FILE" || mv "$TMPFILE" "$RESUME_FILE"
```

### Phase 2 — `/tmp/claude-*` cleanup

```bash
# Candidates: regular files in /tmp matching claude-* with mtime >= session
# floor.
#
# `-f` (regular files only), NOT `-e`: /tmp/claude-<uid> is the harness's own
# scratchpad ROOT — one directory holding every project's and every session's
# scratchpad, including the live one. It matches the glob and its mtime is
# always current, so `-e` would offer it as candidate #1 on every run.
#
# Portable mtime compare — BSD/macOS `find` rejects `-newermt "@epoch"`, so the
# old form silently matched nothing on the whole macOS fleet. Use `stat`, GNU
# form FIRST: BSD `stat` rejects `-c` with a usage error on stderr and prints
# nothing to stdout, so the fallback fires cleanly. The reverse order does not
# fall back — GNU's `-f` takes no argument, so `%m` is read as a filename and
# GNU still prints a filesystem block for "$p" to stdout, which the command
# substitution captures.
CANDIDATES="$(
  for p in /tmp/claude-*; do
    [ -f "$p" ] || continue
    m="$(stat -c '%Y' "$p" 2>/dev/null || stat -f '%m' "$p" 2>/dev/null)"
    [ -n "$m" ] && [ "$m" -ge "$SESSION_FLOOR" ] && printf '%s\n' "$p"
  done
)"
```

If `$CANDIDATES` empty, print "Phase 2: no `/tmp/claude-*` candidates from this session — skipping." and continue.

Otherwise, enumerate with size + age:

```
Phase 2 — /tmp/claude-* cleanup candidates:
  [1] /tmp/claude-abc123    412K    3h ago
  [2] /tmp/claude-def456     12K    1h ago

Delete which? [1,2 / all / skip]
```

- On numeric selection or `all`: `rm <path>` for each (unless `DRY_RUN=1`).
- On `skip`: continue to phase 3 with no deletions.

**Defense-in-depth check before every `rm`:** the path MUST start with `/tmp/claude-`; reject otherwise.

Report phase summary: `Phase 2: deleted N files, reclaimed M bytes, skipped K.`

### Phase 3 — `.claude/settings.json` + `.claude/settings.local.json` sanity-pass (READ-ONLY)

Phase 3 enumerates **both** settings files in order: the project-checked-in `.claude/settings.json` first, then the operator-local `.claude/settings.local.json`. The second file is what actually accumulates session-scoped `permissions.allow` adds on operator machines — Claude Code writes session grants there, not to the checked-in file. A per-file header is emitted so the operator can tell which file each candidate belongs to.

```bash
SETTINGS_FILES=(
  "$CURRENT_ROOT/.claude/settings.json"
  "$CURRENT_ROOT/.claude/settings.local.json"
)

# Capture pre-phase invariants (mtime + size) for each present file
declare -A SETTINGS_PRE
for f in "${SETTINGS_FILES[@]}"; do
  if [ -f "$f" ]; then
    SETTINGS_PRE["$f"]="$(stat -f '%m:%z' "$f" 2>/dev/null || stat -c '%Y:%s' "$f" 2>/dev/null)"
  fi
done

ANY_FOUND=0
for f in "${SETTINGS_FILES[@]}"; do
  [ -f "$f" ] || continue
  ANY_FOUND=1
  rel="${f#$CURRENT_ROOT/}"
  echo "--- Phase 3 — $rel ---"
  # Three sharper "session-scoped" heuristics applied per permissions.allow entry:
  #   (h1) absolute /Volumes/AIML0NN/... paths
  #   (h2) long literal arg strings (>100 chars; embedded newlines also qualify)
  #   (h3) literal full commands with no glob metacharacters (* or ?)
  jq -r '.permissions.allow // [] | .[]' "$f" 2>/dev/null | while IFS= read -r entry; do
    flag=""
    case "$entry" in
      *"/Volumes/AIML0"*) flag="h1: absolute Volume path" ;;
    esac
    if [ -z "$flag" ] && [ "${#entry}" -gt 100 ]; then
      flag="h2: long literal arg string (${#entry} chars)"
    fi
    if [ -z "$flag" ] && ! printf '%s' "$entry" | grep -qE '[*?]'; then
      flag="h3: literal full command (no glob metacharacters)"
    fi
    [ -n "$flag" ] && printf '  candidate: %s\n    reason: %s\n' "$entry" "$flag"
  done
done
[ "$ANY_FOUND" = "0" ] && echo "Phase 3: no .claude/settings*.json files found — skipping."
```

For each flagged candidate, prompt:

```
Phase 3 — session-scoped override candidate:
  File:    .claude/settings.local.json
  Entry:   Bash([ -f "$SETTINGS" ])
  Reason:  h3: literal full command (no glob metacharacters)

Note for revert in resume.md? [y/n]
```

- On **y**: append a bullet to `.local/resume.md` § Open questions, naming the affected file and the heuristic that flagged it:

  ```
  - Revert .claude/settings.local.json entry: `Bash([ -f "$SETTINGS" ])` (h3)
  ```

- On **n**: continue.

**INVARIANT:** this phase NEVER writes to either settings file. The skill verifies each present file's mtime + size match pre/post-phase-3 against the `$SETTINGS_PRE[…]` snapshot captured before enumeration.

### Phase 4 — Working-tree audit (advisory)

```bash
git status --porcelain
```

Parse output into three categories:
- **Unstaged**: leading ` M` or ` D`.
- **Staged**: leading `M ` / `A ` / `D ` / `R `.
- **Untracked**: leading `??`.

Enumerate stashes newer than `$SESSION_FLOOR`:

```bash
git stash list --pretty='%gd %ci %s' | while read -r stash_ref stash_date_iso stash_msg; do
  stash_epoch=$(date -j -f '%Y-%m-%d %H:%M:%S %z' "$stash_date_iso" +%s 2>/dev/null || echo 0)
  [ "$stash_epoch" -ge "$SESSION_FLOOR" ] && echo "$stash_ref $stash_msg"
done
```

For EACH item across the four buckets, present:

```
Phase 4 — working-tree item:
  Category:  unstaged
  Path:      meta/scripts/foo.sh

Action? [(a) commit now / (b) stash with auto-tagged message / (c) record as open in resume.md / (d) ignore]
```

**Canonical-only guard.** Before option (a) runs, check:

```bash
CANONICAL_ONLY_PATHS_RE='^openspec/(changes/|specs/|decisions\.md$|ideas\.md$|\.openspec\.yaml$)'
FORK_MAIN=0
[[ "$BRANCH" == "main" && "$ORIGIN_URL" != *"alemaxdesign/claude-meta"* ]] && FORK_MAIN=1
```

If `FORK_MAIN=1` and the item path matches `CANONICAL_ONLY_PATHS_RE`, refuse (a) and re-offer (b)(c)(d) with the reason printed: `Canonical-only path on fork main — commit would violate governance.`

**Option (a) — commit now.**

```
Commit message? [default: wip: back-burner snapshot <ISO-date>]
```

```bash
git add "$PATH" && git commit -m "$MSG"   # skip if DRY_RUN=1
echo "Committed: $(git rev-parse HEAD)"
```

**Option (b) — stash with auto-tagged message.**

```bash
git stash push --include-untracked --message "back-burner stash $(date +%Y-%m-%dT%H:%M:%SZ)" -- "$PATH"
STASH_REF="$(git stash list | head -1 | awk '{print $1}' | tr -d :)"
```

Record the stash ref in resume.md § Open questions:

```
- Stashed during back-burner: `<stash_ref>` — `<path>`
```

**Option (c) — record as open in resume.md.**

Append a bullet to § Open questions:

```
- Uncommitted <category>: `<path>` (deliberately left unhandled at wind-down)
```

**Option (d) — ignore.** No-op; proceed to next item.

After the audit completes, **update the resume.md frontmatter `working_tree_clean` field** in-place:

```bash
if git diff-index --quiet HEAD -- 2>/dev/null && [ -z "$(git status --porcelain)" ]; then
  WTC=true
else
  WTC=false
fi
# In-place sed: replace "working_tree_clean: false" with "working_tree_clean: $WTC" within the frontmatter block
sed -i.bak "1,/^---$/{s/^working_tree_clean: false/working_tree_clean: $WTC/;}" "$RESUME_FILE" && rm -f "${RESUME_FILE}.bak"
```

### Phase 5 — Handoff prompt

Print **exactly** this text (and nothing else, except optionally a partial-completion summary if earlier phases were skipped):

```
Wind-down complete. Run /compact, then /quit when ready.
```

If any earlier phase was skipped, prepend:

```
Ran phases: <list>. Skipped: <list>.
```

**INVARIANT:** the skill SHALL NOT invoke `/compact`, `/quit`, or any other slash command from phase 5. It SHALL NOT spawn a subprocess that would. The phase 5 print is the last action.

## Edge cases

- **Operator types Ctrl-C mid-flow** — whatever phase has committed mutations stays committed (e.g., a phase-4 commit is real). The skill exits cleanly with no rollback.
- **`.local/resume.md` already exists** — phase 1 overwrites unconditionally. Prior versions are not preserved (the operator's git tooling does not track `.local/`).
- **`/tmp/claude-*` enumeration finds nothing** — phase 2 reports "no candidates" and continues to phase 3.
- **`.claude/settings.json` or `.claude/settings.local.json` is malformed JSON** — phase 3 reports the affected file as "could not parse — skipping", then continues to the next settings file (or to phase 4 if no more files).
- **Phase 4 audit finds zero items** — phase 4 reports "working tree clean" and the post-audit frontmatter update sets `working_tree_clean: true`.
- **Operator passes `--dry-run`** — every mutating action becomes a `[dry-run] would …` log line; the skill walks all five phases but writes nothing.

## system-path-rule

This skill operates exclusively under the current repo's `.local/` (for `resume.md`), the current repo's `.gitignore` (for the precondition), the current repo's `.claude/settings.json` + `.claude/settings.local.json` (both read-only), and `/tmp/claude-*` (constrained-prefix cleanup). No macOS-system-rooted paths beyond `/tmp` are touched.

## Cross-links

- `openspec/specs/back-burner-session-wind-down/spec.md` — canonical schema + behavioral spec for this skill.
- `openspec/specs/spec-governance/spec.md` — `.local/` convention from `dot-local-scratch-convention` (archived 2026-06-01).
- `openspec/specs/alemax-skills/spec.md` — family conventions + `context: either` declaration requirement from `alemax-skills-context-awareness` (archived 2026-06-01).
- `.claude/skills/alemax-front-burner/SKILL.md` — paired consumer skill that reads `.local/resume.md` on next session start (sibling change `front-burner-session-resume`).
- `meta/docs/ALEMAX-SKILLS.md` — family roster.

---
name: alemax-collect-feedback
description: Drain `.local/feedback.md` from every project in the operator's `projects.yaml`, three-stage-classify each finding (dedup against archived/in-flight changes + harness-vs-claude-meta + operator confirmation), and emit a single canonical PR appending surviving findings to `openspec/ideas.md` § Raw ideas. Annotates source rows post-collection so re-runs skip already-collected entries. Closes the alemax-feedback cluster: `/alemax:feedback` captures + `/alemax:diagnose` scaffolds + `/alemax:collect-feedback` collects.
license: MIT
compatibility: Requires bash, git, gh, yq. Runs from the meta-repo clone (claude-meta-only). Honors the canonical-only governance rule.
context: claude-meta-only
metadata:
  author: alemax
  version: "1.0"
---

## Wraps

No single shell script. The workflow is: walk the operator's `projects.yaml`, read `.local/feedback.md` from each project, three-stage-classify each row, emit a canonical PR, annotate consumed rows.

The skill is the harvest half of the alemax-feedback cluster. `/alemax:feedback` (already shipped) captures findings per-project; this skill batches them into a canonical PR matching PR #80's shape.

## The collection story

Over a session-or-three an operator accumulates findings across projects — `american-dream/.local/feedback.md` carries 8 rows; `cookie-monster/.local/feedback.md` carries 3. At end-of-week (or whenever) the operator wants to drain all of them into the claude-meta backlog without re-deriving "which already shipped" and "which is harness territory" by hand.

This skill is that workflow. Per-row classification through three stages (dedup → harness → operator confirmation), aggregated into a single canonical PR. Annotation pass post-collection means re-running is idempotent — only NEW rows surface next time.

## Behavior overview

1. **Step 0 — Context check.** Refuse if invoked from outside the meta-repo (matches the other claude-meta-only skills).
2. **Step 1 — Preflight.** Clean tree, `projects.yaml` exists, `yq` available.
3. **Step 2 — Walk `projects.yaml`.** Extract `(name, path)` pairs.
4. **Step 3 — Per-project parse.** For each project, check `.local/feedback.md` exists, parse rows.
5. **Step 4 — Stage 1: dedup.** Text-match each finding against archived + active changes. Surface candidates per row.
6. **Step 5 — Stage 2: harness classification.** Keyword heuristic per row; prompt on ambiguous.
7. **Step 6 — Stage 3: aggregated confirmation table.** Operator confirms / overrides per row.
8. **Step 7 — PR emission.** Branch, append `[ ]` entries to `openspec/ideas.md`, commit, push, open PR.
9. **Step 8 — Post-collection annotation.** Append `(collected YYYY-MM-DD → PR #<num>)` to each consumed row's H3 heading in its source `.local/feedback.md`.

## Steps

### Step 0 — Context check

```bash
CURRENT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ "$ORIGIN_URL" == *"claude-meta"* && "$CURRENT_ROOT" == *"/claude-meta" ]]; then
  CURRENT_CONTEXT="claude-meta"
else
  CURRENT_CONTEXT="project"
fi
if [[ "$CURRENT_CONTEXT" != "claude-meta" ]]; then
  echo "ERROR: alemax-collect-feedback requires context: claude-meta-only but you're in: $CURRENT_CONTEXT" >&2
  echo "  current:    $CURRENT_ROOT" >&2
  echo "" >&2
  echo "This skill walks projects.yaml and opens a PR against canonical claude-meta; both require a meta-repo starting point." >&2
  echo "To proceed, cd to your meta-repo clone (typically: /Volumes/AIML0NN/Users/<u>/claude-code/<ghhandle>/claude-meta)." >&2
  exit 1
fi
META_ROOT="$CURRENT_ROOT"
```

### Step 1 — Preflight

```bash
if ! git diff-index --quiet HEAD --; then
  echo "ERROR: working tree dirty — commit or stash first" >&2
  exit 1
fi
[ -f "$META_ROOT/projects.yaml" ] || { echo "ERROR: projects.yaml not found at $META_ROOT" >&2; exit 1; }
command -v yq >/dev/null || { echo "ERROR: yq not on PATH" >&2; exit 1; }
TODAY="$(date +%Y-%m-%d)"
```

### Step 2 — Walk `projects.yaml`

```bash
# Extract (name, path) for active projects — the manifest field is .path (written by meta/bootstrap/lib/manifest.sh:manifest_upsert)
yq -r '.projects[] | select(.status == "active") | .name + "\t" + .path' "$META_ROOT/projects.yaml"
```

Capture into a `projects_with_feedback` array — for each project, check `path/.local/feedback.md` exists.

### Step 2b — Implicit meta-repo source

The meta-repo itself is a valid source. `/alemax:feedback` declares `context: either` and writes to `$META_ROOT/.local/feedback.md` when invoked from the meta-repo clone. Append the meta-repo as a fixed extra source after the `projects.yaml` walk:

```bash
# Append the meta-repo as an implicit source under the project name "claude-meta"
sources_with_feedback+=("claude-meta	$META_ROOT")
```

The meta-repo is NOT in `projects.yaml` by design — CLAUDE.md invariant: "It is not a project itself and is not listed in `projects.yaml`". Treating it as a fixed extra source preserves the invariant while making meta-flavored findings reachable. Rows sourced from the meta-repo appear in collection output and PR tables with the project-name column set to `claude-meta`.

### Step 3 — Per-project parse

For each source (project from `projects.yaml`, or the meta-repo itself under the name `claude-meta` with path `$META_ROOT`):

```bash
FB="$PROJECT_PATH/.local/feedback.md"
[ -f "$FB" ] || continue  # silent skip — operator hasn't captured anything here

# Parse rows: each row starts at "### YYYY-MM-DD HH:MM — <severity>"
# Skip rows already annotated with "(collected ..." (post-collection marker)
awk '
  /^### [0-9]{4}-[0-9]{2}-[0-9]{2}/ {
    if (current_row) print current_row
    if (/\(collected /) { skip = 1 } else { skip = 0 }
    current_row = $0
    next
  }
  !skip { current_row = current_row "\n" $0 }
  END { if (current_row && !skip) print current_row }
' "$FB"
```

Build an array `parsed_rows[]` of `(project, row_text)` tuples.

### Step 4 — Stage 1: dedup against archived + active changes

For each parsed row:

```bash
# Extract the Finding field
FINDING=$(echo "$ROW_TEXT" | grep '^\*\*Finding:\*\*' | sed 's/^\*\*Finding:\*\* *//')

# Compute candidates from archived + active proposals
CANDIDATES=$(grep -lr "$KEY_TERMS_FROM_FINDING" "$META_ROOT/openspec/changes/archive/"*/proposal.md "$META_ROOT/openspec/changes/"*/proposal.md 2>/dev/null)
```

Per row with candidates, prompt:

```
Finding (from <project>): "<finding-excerpt>"

This finding shares keywords with:
  - openspec/changes/archive/2026-06-01-<archived-slug>/  (already shipped)
  - openspec/changes/<active-slug>/                       (in-flight)

Same issue or different? [y=skip (duplicate)/n=keep/k=keep with note]
```

Capture per-row decisions.

### Step 5 — Stage 2: harness classification

Keyword heuristics:

```bash
# Harness territory keywords
HARNESS_KEYWORDS='TodoWrite|Bash CWD|Skill tool|harness|Claude Code prompt|skill prompt verbosity|Monitor|RemoteTrigger'

# claude-meta backlog keywords
META_KEYWORDS='init-project|scaffolding/|meta/|openspec/|init-user.sh|\.zshenv|aiml drive|init-machine|sync-from-meta'

for row in surviving rows; do
  if echo "$ROW_TEXT" | grep -qiE "$HARNESS_KEYWORDS"; then
    DEFAULT_CLASS="harness"
  elif echo "$ROW_TEXT" | grep -qiE "$META_KEYWORDS"; then
    DEFAULT_CLASS="meta"
  else
    DEFAULT_CLASS="ambiguous"
  fi
done
```

For ambiguous rows, prompt:

```
Finding: "<finding>"
Is this Anthropic-harness territory (Claude Code itself) or claude-meta backlog?
  [h=harness/m=meta/s=skip]
```

### Step 6 — Stage 3: aggregated confirmation table

Present the full picture:

```
Collection summary (run YYYY-MM-DD):

Found 11 rows across 2 projects.

KEEP (8 → ideas.md):
  | Project          | Severity | One-liner                                  | Slug-proposed                 |
  |------------------|----------|--------------------------------------------|-------------------------------|
  | american-dream   | friction | Missing expo-crypto package; Hermes crash  | mobile-expo-stack-profile-2   |
  | ...

OMIT — already shipped (2):
  | Finding                              | Shipped via                              |
  | TodoWrite progress tracking missing  | opsx-skills-todowrite-fallback (2026-06-01) |
  | ...

OMIT — harness territory (1):
  | Finding                          | Reason                              |
  | Skill prompt verbose             | Anthropic-feedback; not meta-backlog |

Proceed with PR? [y/n/edit row N]
```

`edit row N` lets the operator override classification for a specific row.

The `Project` column carries either a `projects.yaml` name (e.g., `american-dream`, `todo-list`) for project-sourced rows or the literal `claude-meta` for rows sourced from `$META_ROOT/.local/feedback.md` per Step 2b. Operators reading the table can distinguish meta-territory findings at a glance.

Bulk-accept option: skill accepts `--yes-all` to skip per-row prompts but still presents this aggregated table.

### Step 7 — PR emission

On operator confirmation:

```bash
BRANCH="chore/collect-feedback-$TODAY"
git checkout -b "$BRANCH"

# Append [ ] entries to openspec/ideas.md § Raw ideas
TMPFILE="$(mktemp)"
{
  cat openspec/ideas.md
  printf '\n'
  for KEEP_ROW in surviving_rows; do
    printf '%s\n\n' "$(format_idea_entry "$KEEP_ROW")"
  done
} > "$TMPFILE"
mv "$TMPFILE" openspec/ideas.md

git add openspec/ideas.md
git commit -m "ideas: collected feedback from N projects (YYYY-MM-DD)"
git push -u origin "$BRANCH"

# Open PR matching PR #80's shape
gh pr create --base main --title "ideas: collected feedback from N projects" --body "$(generate_pr_body)"
```

PR body template (inline; matches PR #80's shape):

```markdown
## Summary

Drained N findings from M projects via `/alemax:collect-feedback` on YYYY-MM-DD.

K surviving findings land as new `[ ]` entries in § Raw ideas (this PR).
L findings omitted (already shipped or harness-territory).

## The cluster

| Slug | One-liner | From | Severity |
|---|---|---|---|
| ... | ... | ... | ... |

## Intentionally omitted

| Finding | Reason |
|---|---|
| ... | Already shipped via [`<archived-change>`](changes/archive/.../) |
| ... | Harness territory — annotated for Anthropic-feedback channel; not claude-meta backlog |
```

Capture the PR number from `gh pr create` output for the annotation pass.

### Step 8 — Post-collection annotation

For each consumed row:

```bash
PR_NUM=<extracted from gh pr create>
for ROW_FILE in source_files; do
  # Append "(collected YYYY-MM-DD → PR #N)" to the H3 heading line
  sed -i '' -E "
    s|^(### [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} — (blocker|friction|idea|harness))$|\\1 (collected $TODAY → PR #$PR_NUM)|
  " "$ROW_FILE"
done
```

The sed pattern only matches H3 headings that DON'T already carry a `(collected ...` annotation — re-runs are safe.

## Edge cases

- **Project's `path` missing.** Skill emits `warn: <project>: path <path> not found, skipping` and continues. Final summary reports K/M projects had feedback + N projects skipped due to missing path.
- **Meta-repo `$META_ROOT/.local/feedback.md` absent.** Silently skipped, same as projects without the file — Step 2b adds the meta-repo as a source but does not require it to have rows.
- **`.local/feedback.md` exists but is empty or malformed.** Skill emits `warn: <project>: no parseable rows in <path>, skipping` and continues.
- **Operator picks `skip` for all rows.** Skill exits cleanly without opening a PR; reports "No findings to collect".
- **Two findings in the same project share a slug.** Skill appends `-2`, `-3` to disambiguate (matches the `/alemax:diagnose` pattern).
- **gh PR creation fails** (e.g., network). Skill leaves the branch in place, emits the failure, exits 1. Operator can `gh pr create` manually OR re-run the skill (annotation pass hasn't happened, so re-run is safe).
- **Annotation step fails partway** (e.g., file became read-only). Skill warns + lists which files succeeded/failed; operator hand-annotates the rest.

## system-path-rule

This skill operates exclusively under `meta/`, `openspec/`, and per-project `.local/`. No macOS-system-rooted paths involved.

## Cross-links

- `openspec/specs/alemax-skills/spec.md` — family conventions + this skill's requirement.
- `.claude/skills/alemax-feedback/SKILL.md` — sibling skill; produces the `.local/feedback.md` rows this skill consumes.
- `.claude/skills/alemax-import-ideas/SKILL.md` — annotation pattern reference (mobile-capture cousin).
- PR #80 (https://github.com/alemaxdesign/claude-meta/pull/80) — the worked example whose PR shape this skill formalizes.
- `openspec/specs/spec-governance/spec.md` — `.local/` convention; canonical-only governance.

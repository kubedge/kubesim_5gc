---
name: alemax-import-ideas
description: Drain an Obsidian vault of mobile-captured ideas — walk the vault for `ideas-on-the-go(-<projectname>)?.md` files, route each file by its filename (cross-cutting for the un-suffixed or `-claude-meta` form; existing-project for `-<project>` matching `projects.yaml`; new-project-chain for unknown names with operator confirmation), and per row ask only "import? [y/skip-personal]". Default vault is `/Users/<u>/Library/Mobile Documents/iCloud~md~obsidian/Documents/AlemaxIdeas/` (Obsidian's iCloud container) per `obsidian-as-canonical-markdown-surface`. Use after dictating ideas to Obsidian on mobile and wanting to triage them on the desktop.
license: MIT
compatibility: Requires bash, git, gh, yq, jq, and iCloud Drive mounted (it's auto-mounted on macOS for signed-in operators). Obsidian on mobile + desktop is the canonical capture surface; operators using a different markdown-sync app set `users.yaml.ideas_on_the_go_vault` to their chosen vault folder.
context: claude-meta-only
metadata:
  author: alemax
  version: "2.0"
---

## Wraps

No single shell script — the workflow is "walk the Obsidian vault for mobile-captured `ideas-on-the-go(-<projectname>)?.md` files, route each by filename, and per-row ask only yes/skip-personal." The filename has already done the project classification at filing time on mobile, so the desktop session has minimal friction.

This skill embodies the workflow, not a shell wrapper.

## The capture story

The four operators use Obsidian on iPhone (sometimes carplay, sometimes shopping, sometimes can't-sleep-3am). Each operator's Obsidian vault on iPhone is the canonical `AlemaxIdeas/` folder inside Obsidian's own iCloud container — the file syncs to macOS Obsidian over iCloud at no cost (per `obsidian-as-canonical-markdown-surface` in `openspec/specs/alemax-skills/spec.md`).

The naming convention is **filename-driven routing**:

- `ideas-on-the-go.md` (no suffix) or `ideas-on-the-go-claude-meta.md` → ideas route to canonical `alemaxdesign/claude-meta`'s `openspec/ideas.md` (cross-cutting)
- `ideas-on-the-go-<existing-project>.md` (where `<existing-project>` is a name in the operator's `projects.yaml`) → ideas route to that project's `openspec/ideas.md`
- `ideas-on-the-go-<unknown>.md` → skill prompts "Create new project `<unknown>`?" and on yes chains through `/alemax:new-project`

The operator picked the routing at filing time on mobile (by choosing the filename). On desktop the skill just walks the vault, per-file routes, and per-row asks the single question "import this? [y/skip-personal]".

## Behavior overview

1. **Resolve the vault.** Read `users.yaml.ideas_on_the_go_vault` (preferred), fall back to legacy `ideas_on_the_go_path` (deprecated alias with warning), fall back to the literal default. Refuse if the vault folder doesn't exist.
2. **Walk the vault.** Match files against `^ideas-on-the-go(-(.+))?\.md$`, sort by mtime (oldest first). The `<projectname>` capture group is the routing key (empty for un-suffixed).
3. **iCloud freshness check.** If a file's mtime is >5 minutes old AND the operator mentions dictating recently, ask whether to wait for sync. Informational only.
4. **Per-file routing.** Each file's `<projectname>` decides the route via the four branches above. If the same routing target appears twice in the vault (e.g., un-suffixed + explicit `-claude-meta`), emit a once-per-target warn and continue processing both.
5. **Per-entry yes/skip-personal.** Within each routed file, for each pending `- [ ]` row, ask exactly one question: "Import this row? [y/skip-personal]" (default y). The filename already decided routing.
6. **Atomic file rewrite.** Annotate routed/skipped entries in place via tempfile + rename. The route summary includes the source filename.
7. **Final summary.** Per-file counts (routed/skipped) plus aggregate totals.

## Steps

### Step 0 — Argument parsing + context check

```bash
# Parse args. The skill accepts:
#   --dry-run           list pending entries + tentative classification; no mutations
#   --only <project>    project-context bypass — drain only ideas-on-the-go-<project>.md;
#                       allowed from a project clone (relaxes claude-meta-only guard)
DRY_RUN=0
ONLY_PROJECT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --only) ONLY_PROJECT="${2:?--only requires <project>}"; shift 2 ;;
    --) shift; break ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Context check. This skill declares context: claude-meta-only (per frontmatter).
# Refuse if invoked from outside the meta-repo UNLESS --only <project> is set.
CURRENT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ "$ORIGIN_URL" == *"claude-meta"* && "$CURRENT_ROOT" == *"/claude-meta" ]]; then
  CURRENT_CONTEXT="claude-meta"
else
  CURRENT_CONTEXT="project"
fi

if [[ "$CURRENT_CONTEXT" != "claude-meta" && -z "$ONLY_PROJECT" ]]; then
  echo "ERROR: alemax-import-ideas requires context: claude-meta-only but you're in: $CURRENT_CONTEXT" >&2
  echo "  current:    $CURRENT_ROOT" >&2
  echo "" >&2
  echo "This skill opens PRs against canonical claude-meta and per-project repos; both require a claude-meta-side starting point." >&2
  echo "" >&2
  echo "Two ways forward:" >&2
  echo "  (a) cd to your meta-repo clone (typically: /Users/$(whoami)/claude-code/<ghhandle>/claude-meta) and re-run." >&2
  echo "  (b) If the vault contains ONLY this project's ideas-on-the-go-<project>.md, re-run with --only <project>" >&2
  echo "      from this clone. The skill skips cross-cutting + other-project routing entirely." >&2
  exit 1
fi

# When --only is set from a project clone, derive META_ROOT for stage-1 dedup.
# Convention per CLAUDE.md: $AIML_VOLUME/Users/$USER/claude-code/<ghhandle>/<name>.
# meta-repo is a sibling under the same <ghhandle>. Fall back to $META_REPO_PATH env.
if [[ -n "$ONLY_PROJECT" && "$CURRENT_CONTEXT" != "claude-meta" ]]; then
  PROJECT_PARENT="$(dirname "$CURRENT_ROOT")"
  if [[ -d "$PROJECT_PARENT/claude-meta/.git" ]]; then
    META_ROOT="$PROJECT_PARENT/claude-meta"
  elif [[ -n "${META_REPO_PATH:-}" && -d "$META_REPO_PATH/.git" ]]; then
    META_ROOT="$META_REPO_PATH"
  else
    echo "ERROR: --only <project> needs to locate a meta-repo clone for stage-1 dedup." >&2
    echo "  Tried sibling: $PROJECT_PARENT/claude-meta (not found)" >&2
    echo "  Override: export META_REPO_PATH=/path/to/your/claude-meta and re-run." >&2
    exit 1
  fi
  echo "[info] --only $ONLY_PROJECT: bypassing claude-meta-only guard; META_ROOT=$META_ROOT"
fi
```

### Step 1 — Resolve the vault folder

```bash
META_ROOT=$(git -C . rev-parse --show-toplevel)
USERNAME=$(whoami)

# Prefer the new field (ideas_on_the_go_vault); fall back to legacy
# (ideas_on_the_go_path) with a deprecation warn; fall back to the literal
# default per obsidian-as-canonical-markdown-surface.
#
# NOTE: literal /Users/$USERNAME/... per the system-path-rule. Under
# HOME-redirect, $HOME resolves to the SSD but iCloud is a macOS system
# service rooted at /Users/<u>/Library/Mobile Documents/ on the boot disk.
VAULT=$(USER_E="$USERNAME" yq -r '.users[] | select(.username == strenv(USER_E)) | (.ideas_on_the_go_vault // "")' "$META_ROOT/users.yaml" 2>/dev/null)
VAULT_SOURCE="ideas_on_the_go_vault"

if [[ -z "$VAULT" ]]; then
  LEGACY=$(USER_E="$USERNAME" yq -r '.users[] | select(.username == strenv(USER_E)) | (.ideas_on_the_go_path // "")' "$META_ROOT/users.yaml" 2>/dev/null)
  if [[ -n "$LEGACY" ]]; then
    VAULT="$LEGACY"
    VAULT_SOURCE="ideas_on_the_go_path (legacy)"
    echo "[warn] users.yaml uses legacy field 'ideas_on_the_go_path'; rename to 'ideas_on_the_go_vault' (folder semantics). See openspec/specs/mobile-capture/spec.md."
    # Legacy values may point at a file. Strip to parent folder if so.
    [[ -f "$VAULT" ]] && VAULT=$(dirname "$VAULT")
  fi
fi

[[ -z "$VAULT" ]] && VAULT="/Users/$USERNAME/Library/Mobile Documents/iCloud~md~obsidian/Documents/AlemaxIdeas"

# Strip trailing slash for consistency.
VAULT="${VAULT%/}"

if [[ ! -d "$VAULT" ]]; then
  echo "Vault folder not found at: $VAULT"
  echo "  Setup hint: Obsidian's canonical iCloud container is"
  echo "    /Users/$USERNAME/Library/Mobile Documents/iCloud~md~obsidian/Documents/AlemaxIdeas/"
  echo "  Create the folder via Obsidian (Settings → Files → Vault location) on iPhone or Mac;"
  echo "  the folder shows up in iCloud Drive once Obsidian writes anything to it."
  echo "  Override via users.yaml.ideas_on_the_go_vault if you use a different vault location."
  exit 1
fi

echo "[info] vault: $VAULT (source: $VAULT_SOURCE)"
```

### Step 2 — Walk the vault for matching files

```bash
# Match files: ideas-on-the-go.md OR ideas-on-the-go-<anything>.md
# Sort by mtime (oldest first) so older captures get processed first.
# When --only <project> is set, restrict to the single matching filename.
declare -a MATCHED
while IFS= read -r -d '' f; do
  bn=$(basename "$f")
  [[ "$bn" =~ ^ideas-on-the-go(-(.+))?\.md$ ]] || continue
  if [[ -n "$ONLY_PROJECT" ]]; then
    [[ "${BASH_REMATCH[2]:-}" == "$ONLY_PROJECT" ]] || continue
  fi
  MATCHED+=("$f")
done < <(find "$VAULT" -maxdepth 1 -type f -print0 2>/dev/null | xargs -0 -I{} stat -f '%m %N' {} | sort -n | cut -d' ' -f2- | tr '\n' '\0')

if [[ -n "$ONLY_PROJECT" && ${#MATCHED[@]} -eq 0 ]]; then
  echo "[info] --only $ONLY_PROJECT: no ideas-on-the-go-$ONLY_PROJECT.md in $VAULT. Nothing to do."
  exit 0
fi

if [[ ${#MATCHED[@]} -eq 0 ]]; then
  echo "No ideas-on-the-go(-<projectname>)?.md files in $VAULT. Nothing to do."
  exit 0
fi

echo "[info] matched ${#MATCHED[@]} file(s):"
printf '  - %s\n' "${MATCHED[@]##*/}"
```

For each matched file, extract the `<projectname>` from the filename:

```bash
# bn=basename of file. Extract suffix per regex.
extract_projectname() {
  local bn="$1"
  if [[ "$bn" =~ ^ideas-on-the-go(-(.+))?\.md$ ]]; then
    printf '%s' "${BASH_REMATCH[2]}"   # empty for un-suffixed; <name> for suffixed
  fi
}
```

### Step 3 — iCloud freshness check (advisory, per file)

For each matched file:

```bash
file_mtime_sec=$(stat -f %m "$f")
now_sec=$(date +%s)
age_min=$(( (now_sec - file_mtime_sec) / 60 ))
if [[ $age_min -lt 5 ]]; then
  echo "  [info] ${f##*/} modified $age_min min ago — fresh."
elif [[ $age_min -gt 60 ]]; then
  echo "  [info] ${f##*/} modified $age_min min ago — if you just dictated, iCloud sync may not be complete yet."
fi
```

Informational only. Proceed regardless of operator response.

### Step 4 — Per-file routing

Detect duplicate routing targets up front (e.g., both un-suffixed and explicit `-claude-meta`) and warn once:

```bash
# Pre-pass: build the set of routing targets to detect duplicates.
declare -A TARGETS_SEEN
for f in "${MATCHED[@]}"; do
  bn=$(basename "$f")
  proj=$(extract_projectname "$bn")
  target="${proj:-claude-meta}"   # empty suffix maps to claude-meta (cross-cutting)
  if [[ -n "${TARGETS_SEEN[$target]:-}" ]]; then
    echo "[warn] vault has multiple files routing to '$target': '${TARGETS_SEEN[$target]}' and '$bn'. Recommend consolidating into one file."
  else
    TARGETS_SEEN[$target]="$bn"
  fi
done
```

Then for each file, decide the route:

```bash
META_PROJECTS=$(yq -r '.projects[].name' "$META_ROOT/projects.yaml" 2>/dev/null)

route_for_file() {
  local bn="$1"
  local proj
  proj=$(extract_projectname "$bn")

  if [[ -z "$proj" || "$proj" == "claude-meta" ]]; then
    echo "cross-cutting"
    return 0
  fi
  if echo "$META_PROJECTS" | grep -qx "$proj"; then
    echo "existing-project:$proj"
    return 0
  fi
  echo "unknown:$proj"
}
```

Routing branches:

- **`cross-cutting`** — entries route to canonical `alemaxdesign/claude-meta`'s `openspec/ideas.md` via PR (Step 4c).
- **`existing-project:<name>`** — entries route to `<name>`'s local clone + push + PR (Step 4b).
- **`unknown:<name>`** — present the operator with the AskUserQuestion tool:

  > "File `ideas-on-the-go-<name>.md` references a project not in your `projects.yaml`. Create new project `<name>`?"

  Options:
  - **Yes, create** — chain through `/alemax:new-project <name>` (Step 4a). On `/alemax:new-project` completion, route the file's entries to the newly-created project's `openspec/ideas.md`. On chain failure (operator declined bootstrap args, gh error, etc.), annotate the file's pending entries as `[x] (<date> → failed: <reason>; rename file or retry)` and continue with the next file.
  - **No, route as cross-cutting** — entries go to canonical claude-meta's `openspec/ideas.md` (same as Step 4c).
  - **No, skip this file** — leave the file untouched (no annotation); re-runs re-prompt. Useful when the operator wants to rename the file in Obsidian first.
  - **Cancel entire import session** — exit without further changes; partial annotations already written remain (they're idempotent).

### Step 4a — Route: new-project (chained from unknown-suffix branch)

```bash
# Within the operator's claude-meta fork clone:
/alemax:new-project <name>
```

The `/alemax:new-project` skill handles arg-gathering (the operator may revise `<name>`), validation, confirmation, and the `repos.yaml` PR. When it returns successfully, the routed file's entries go to the newly-created project's `openspec/ideas.md` (Step 4b's logic against the new project name).

### Step 4b — Route: existing-project

```bash
PROJECT_PATH=$(NAME_E="$proj" yq -r '.projects[] | select(.name == strenv(NAME_E)) | .path' "$META_ROOT/projects.yaml")
[[ -z "$PROJECT_PATH" || ! -d "$PROJECT_PATH" ]] && { echo "[err] project '$proj' not found locally"; return 1; }

cd "$PROJECT_PATH"
git checkout -B ideas/import-$(date +%Y%m%d)

# For each y-confirmed row in the source file:
echo "- [ ] $IDEA_TEXT (imported from ${bn} on $(date +%Y-%m-%d))" >> openspec/ideas.md

git add openspec/ideas.md
git commit -m "ideas: import from $bn ($(date +%Y-%m-%d))"
git push -u origin HEAD
gh pr create --fill --base main
```

(Operator merges manually.)

### Step 4c — Route: cross-cutting (canonical claude-meta)

```bash
# Per openspec-governance-canonical-only: feature branch + PR to canonical.
# NEVER fork main.
cd "$META_ROOT"
git checkout -B ideas/import-$(date +%Y%m%d)

# For each y-confirmed row in the source file:
echo "- [ ] $IDEA_TEXT (imported from ${bn} on $(date +%Y-%m-%d))" >> openspec/ideas.md

git add openspec/ideas.md
git commit -m "ideas: import from $bn ($(date +%Y-%m-%d))"
git push -u origin HEAD
gh pr create --fill --base main --repo alemaxdesign/claude-meta
```

### Step 4d — Per-row yes/skip-personal

Within each routed file, for each pending `- [ ]` row, present it and use the **AskUserQuestion tool**:

> "Import this row? [y/skip-personal]" (default y)

- **y** → process per the file's route (Step 4a/b/c) and annotate the row in Step 5.
- **skip-personal** → annotate the row as `[x] (skipped: personal)` and move on; no git/gh action.

There is no per-row routing classification. The filename already decided that.

If the row text is genuinely two ideas combined, the operator can say "actually split this into two" — the skill re-asks after the operator manually edits the source file in Obsidian. Or the operator can `skip-personal` this run and split later.

### Step 5 — Annotate the source row (with source filename in the summary)

Atomic file rewrite — tempfile + rename. Never `sed -i` directly on the vault file (iCloud Drive doesn't always handle in-place writes well).

For each row, rewrite from:

```
- [ ] <text>
```

to one of:

```
- [x] (2026-06-01 → new-project: <new-name> via ideas-on-the-go-<unknown>.md) <text>
- [x] (2026-06-01 → existing-project: <name>, PR #<num> via ideas-on-the-go-<name>.md) <text>
- [x] (2026-06-01 → cross-cutting, PR #<num> via ideas-on-the-go.md) <text>
- [x] (2026-06-01 → skipped: personal via <source-filename>) <text>
- [x] (2026-06-01 → failed: <reason>; rename file or retry via <source-filename>) <text>
```

The `via <source-filename>` suffix makes re-run audits and triage easier (you see at a glance which file an annotated entry came from).

```bash
tmp=$(mktemp)
awk -v line="$LINENUM" -v new="- [x] ($(date +%Y-%m-%d) → $ROUTE_SUMMARY via $(basename "$f")) $TEXT" \
  'NR == line {print new; next} {print}' "$f" > "$tmp"
mv "$tmp" "$f"
```

### Step 6 — Final summary

Break down by file, then aggregate:

```
Processed 3 vault files:

  ideas-on-the-go.md (cross-cutting)
    ✓ 2 routed (PR #45)
    ⊘ 1 skipped (personal)

  ideas-on-the-go-bookmark-merger.md (existing-project: bookmark-merger)
    ✓ 4 routed (PR #46)
    ⊘ 0 skipped

  ideas-on-the-go-new-thing.md (new-project: new-thing)
    ⊘ 3 skipped (chain failed: gh repo create returned 422 name taken)

Aggregate:
  ✓ 6 routed across 2 PRs
  ⊘ 4 skipped/failed
  Source: /Users/<u>/Library/Mobile Documents/iCloud~md~obsidian/Documents/AlemaxIdeas/
```

## Guardrails

- **Never modify a vault file without a confirmed yes/skip-personal for each pending row.** Operator confirms per row.
- **Never `git commit --no-verify`** to bypass hooks (canonical-only rule).
- **Never write to fork main.** Every PR is feature-branch + PR per `[[openspec-governance-canonical-only]]`.
- **Never auto-merge** PRs. Operator merges after review.
- **Never SSH** anywhere; pure GitHub workflow.
- **Read-only on iCloud** for files in the vault that DON'T match the `ideas-on-the-go(-(.+))?\.md` pattern. The skill's only iCloud writes are annotations in matched files.

## Failure modes

| Symptom | Likely cause | Recovery |
|---|---|---|
| Vault folder missing | Obsidian not installed, or `AlemaxIdeas/` vault not created in Obsidian's iCloud container | Operator creates the vault via Obsidian (Settings → Files → Vault location) on iPhone or Mac; or sets `users.yaml.ideas_on_the_go_vault` to a different folder |
| Vault file content stale | iCloud sync lag | Wait 1-5 min; retry. Skill prints mtime hint per file |
| Unrecognized filename in vault | File doesn't match `ideas-on-the-go(-(.+))?\.md` regex | File is ignored by the skill (not part of the capture queue). `doctor-user.sh` Check 6b warns on unrecognized files in the vault |
| Unknown `<projectname>` in filename | Operator dictated into `ideas-on-the-go-<name>.md` for a project not in `projects.yaml` (typo or new project) | Skill prompts "Create new project `<name>`?"; on `n` ask cross-cutting/skip/cancel |
| `/alemax:new-project` chain fails mid-flow | gh repo collision, operator declined args, gh API error | Entries annotated `[x] (failed: <reason>; rename file or retry)`; re-runs skip them until source file is edited |
| Existing-project route: project name not in fork's projects.yaml | File suffix matches a project that's been removed/renamed | Skill treats as unknown-`<projectname>` branch (prompt to create) |
| PR creation fails (gh auth, repo perms) | Operator's PAT lacks permissions | Surface the gh error; operator fixes auth and retries the specific entry |
| Legacy `ideas_on_the_go_path` field set | Operator hasn't renamed since `obsidian-as-canonical-markdown-surface` shipped | Skill emits deprecation warn but still resolves the value. Rename the field at convenience. |

## See also

- `meta/docs/ALEMAX-SKILLS.md` — family conventions
- `meta/docs/HOW-TO-USE-CLAUDE.md` § Section 3 — the `obsidian-as-canonical-markdown-surface` and `system-path-rule` callouts
- `meta/docs/HOW-TO-COLLABORATE.md` — where this fits in the daily flow
- `openspec/specs/alemax-skills/spec.md` — `obsidian-as-canonical-markdown-surface` + `system-path-rule` family principles
- `openspec/specs/mobile-capture/spec.md` — vault schema, walk + per-filename routing, collapsed per-entry classification
- `[[openspec-governance-canonical-only]]` — why every route opens a PR, never a direct commit to fork main

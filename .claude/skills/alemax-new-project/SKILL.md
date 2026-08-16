---
name: alemax-new-project
description: Bootstrap a new project in the operator's fork-managed claude-meta workflow. Conversational front-end for meta/bootstrap/init-project.sh — gather args (name, stack, ghhandle, description), validate, confirm side effects, invoke the script, then handle the post-bootstrap projects.yaml + repos.yaml flow. Use when the operator wants to start a new project from inside a Claude session without exiting to the shell.
license: MIT
compatibility: Requires bash, git, gh, yq, uv (for python stack), and the alemaxdesign/claude-meta fork model live.
context: claude-meta-only
metadata:
  author: alemax
  version: "1.0"
---

## Wraps

`meta/bootstrap/init-project.sh` — the 12-phase bootstrap script (arg validate → preflight → git init → rsync templates → render placeholders → run stack script → copy claude/ → openspec init → package init → pre-commit → initial commit → gh repo create → push → branch protection → manifest upsert).

This skill never duplicates the script's logic; it gathers inputs conversationally, validates, confirms, invokes.

## Behavior overview

1. **Detect context.** Where is Claude running? Run `git rev-parse --show-toplevel` + `git remote get-url origin`. The skill works correctly when invoked from inside the operator's claude-meta fork clone OR from any other directory (it'll find the meta repo via the META_ROOT discovery the script does).
2. **Gather args conversationally** (steps below). Skip any that are already inferable from the operator's request.
3. **Validate** the gathered args.
4. **Present the plan** with every side effect named.
5. **Confirm explicitly** — wait for "OK" / "yes" / "proceed".
6. **Invoke** `meta/bootstrap/init-project.sh` with the gathered args.
7. **Report** the outcome + next-step command.

`projects.yaml` and `repos.yaml` are both fork-divergent ([[empty-canonical-projects-yaml]], [[empty-canonical-repos-yaml]]) — entries live as direct commits on the operator's current `aiml0NN` per-drive branch, never as PRs to canonical. The 12-phase script handles `projects.yaml`; the skill's post-bootstrap step handles `repos.yaml` the same way. The skill never mutates canonical-only state ([[openspec-governance-canonical-only]] does not bite here).

## Steps

### Step 0 — Context check

```bash
# This skill declares context: claude-meta-only (per frontmatter).
# Refuse if invoked from outside the meta-repo (per alemax-skills/spec.md).
CURRENT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ "$ORIGIN_URL" == *"claude-meta"* && "$CURRENT_ROOT" == *"/claude-meta" ]]; then
  CURRENT_CONTEXT="claude-meta"
else
  CURRENT_CONTEXT="project"
fi
if [[ "$CURRENT_CONTEXT" != "claude-meta" ]]; then
  echo "ERROR: alemax-new-project requires context: claude-meta-only but you're in: $CURRENT_CONTEXT" >&2
  echo "  current:    $CURRENT_ROOT" >&2
  echo "" >&2
  echo "This skill mutates projects.yaml and runs meta/bootstrap/init-project.sh; both live in claude-meta." >&2
  echo "To proceed, cd to your meta-repo clone (typically: /Volumes/AIML0NN/Users/<u>/claude-code/<ghhandle>/claude-meta)." >&2
  exit 1
fi

# Branch assertion: must be on main or an aiml0NN per-drive branch.
# Fork-divergent commits land on aiml0NN; refuse on a feature branch / detached HEAD.
CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo "<detached>")"
if [[ ! "$CURRENT_BRANCH" =~ ^(main|aiml[0-9]{2})$ ]]; then
  echo "ERROR: current branch '$CURRENT_BRANCH' is neither 'main' nor an aiml0NN per-drive branch." >&2
  echo "Switch to your aiml0NN branch before invoking this skill — \`git checkout aiml0NN\`." >&2
  exit 1
fi
```

### Step 1 — Preflight checks

Before any prompting, verify (in order — fork-sync first; cheap local-git checks only, no shell-out to `fork-sync.sh --dry-run`):

```bash
# Fork-sync: is fork's main behind upstream/main?
BEHIND_MAIN="$(git rev-list --count main..upstream/main 2>/dev/null || echo 0)"
if [[ "$BEHIND_MAIN" -gt 0 ]]; then
  echo "ERROR: fork's main is $BEHIND_MAIN commits behind upstream/main." >&2
  echo "Run \`./meta/scripts/fork-sync.sh --non-interactive --push\` to sync, then retry." >&2
  exit 1
fi

# Fork-sync: when on an aiml0NN branch, is it behind main?
if [[ "$CURRENT_BRANCH" =~ ^aiml[0-9]{2}$ ]]; then
  BEHIND_AIML="$(git rev-list --count HEAD..main 2>/dev/null || echo 0)"
  if [[ "$BEHIND_AIML" -gt 0 ]]; then
    echo "ERROR: $CURRENT_BRANCH is $BEHIND_AIML commits behind main." >&2
    echo "Run \`./meta/scripts/fork-sync.sh --non-interactive --push\` to sync the two-hop chain, then retry." >&2
    exit 1
  fi
fi

# Is the AIML SSD mounted?
[[ -d /Volumes/AIML01 ]] || echo "SSD not mounted"

# Is gh authenticated?
gh auth status >/dev/null 2>&1

# Is the meta-repo's working tree clean?
git status --porcelain
```

If any preflight fails, **stop** and tell the operator which check failed + how to fix it. Do not proceed with gathering args.

The fork-sync checks use `git rev-list --count` directly rather than parsing `fork-sync.sh --dry-run` output — the cheap counts are the same metric `fork-sync.sh` itself computes, and re-implementing them inline avoids coupling to the script's output format. The script remains the recovery action, not the detection mechanism.

### Step 2 — Gather args

Ask only for what's missing. The operator's initial request often contains some args:

- "I want to make a new project called `bookmark-merger` in python" → name + stack inferred; ghhandle + description still needed.
- "build me a CLI tool for sorting my downloads folder" → none inferred; ask all four.

Use the **AskUserQuestion tool** when asking. Group related questions (don't ask name in one turn and stack in another if both are missing).

**The four args:**

| Arg | Format | Source / hints |
|---|---|---|
| `name` | kebab-case (`bookmark-merger`); unique in `projects.yaml` | Operator's description; derive from the noun ("bookmark merger" → `bookmark-merger`) |
| `stack` | `python` or `bash` (only) | Default `python` unless operator says "shell script", "bash", or the project is obviously a one-file utility |
| `ghhandle` | GitHub org/user name | Default `alemaxdesign` for team work; offer alternatives if operator mentions an org or personal namespace |
| `description` | one-liner, ≤80 chars | Operator's own words; rephrase only if it exceeds 80 chars |

### Step 3 — Validate

Run these checks before presenting the plan. Use the bash tool:

```bash
# Name: kebab-case
[[ "$NAME" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] || echo "name not kebab-case"

# Name: unique in projects.yaml
META_ROOT=$(cd "$(git rev-parse --show-toplevel)" && pwd)
yq -e ".projects[] | select(.name == \"$NAME\")" "$META_ROOT/projects.yaml" \
  2>/dev/null && echo "name already in projects.yaml"

# Stack: only python or bash
[[ "$STACK" == "python" || "$STACK" == "bash" ]] || echo "stack must be python or bash"

# ghhandle: in orgs.yaml (warn-only if not).
# orgs.yaml is a LIST of objects keyed by `.owner` (a YAML sequence) — iterate
# with `select`, never map-index (`.orgs["h"]` never matches a seq). Keep a
# genuinely-absent handle (warn) distinct from an unreadable/malformed manifest
# (surface yq's error instead of silently reporting the handle as absent).
if ! orgs_hit=$(yq ".orgs[] | select(.owner == \"$GHHANDLE\")" "$META_ROOT/orgs.yaml" 2>&1); then
  echo "orgs.yaml at $META_ROOT/orgs.yaml is unreadable: $orgs_hit" >&2
elif ! yq -e '.orgs | tag == "!!seq"' "$META_ROOT/orgs.yaml" >/dev/null 2>&1; then
  echo "orgs.yaml at $META_ROOT/orgs.yaml has no '.orgs' list — cannot validate ghhandle" >&2
elif [[ -z "$orgs_hit" ]]; then
  echo "ghhandle '$GHHANDLE' not in orgs.yaml"
fi

# Local clone collision
[[ -d "/Volumes/AIML01/Users/$USER/claude-code/$GHHANDLE/$NAME" ]] \
  && echo "local clone already exists"

# GitHub repo collision
gh repo view "$GHHANDLE/$NAME" >/dev/null 2>&1 && echo "GitHub repo exists"
```

If any validation fails, tell the operator and ask whether to refine the arg or to handle the collision (e.g., delete the existing local dir, pick a different name).

If `ghhandle` isn't in `orgs.yaml`, offer two paths:
1. Proceed without org-context tooling (`discover-repos.sh` won't scan it; lint warns).
2. Add the org to `orgs.yaml` first — direct commit on the current `aiml0NN` branch (`orgs.yaml` is fork-divergent, parallel to `projects.yaml` and `repos.yaml`).

### Step 4 — Present the plan

Summarize every side effect. Use a code block for clarity:

```
About to run: meta/bootstrap/init-project.sh

  --name <name>
  --stack <stack>
  --ghhandle <handle>
  --description "<desc>"

Side effects:
  1. mkdir /Volumes/AIML01/Users/<u>/claude-code/<handle>/<name>/
  2. git init + 12-phase scaffolding (templates, claude/, openspec/, pre-commit)
  3. gh repo create --private <handle>/<name>
  4. Initial commit + push
  5. Best-effort branch protection
  6. projects.yaml entry upsert (in this fork)
  7. claude-meta commit: chore(manifest): activate <name> (<handle>)
  8. repos.yaml entry — direct commit on current aiml0NN branch (fork-divergent)

After the script finishes:
  cd /Volumes/AIML01/Users/<u>/claude-code/<handle>/<name>/ && claude
```

### Step 5 — Confirm explicitly

Use the **AskUserQuestion tool** with explicit yes/no options. Do not infer "OK" from anything short of an unambiguous affirmation. Phrasing the question with the verb the operator should hear ("ready to invoke?") works well.

### Step 6 — Invoke

```bash
cd "$META_ROOT"
./meta/bootstrap/init-project.sh \
  --name "$NAME" \
  --stack "$STACK" \
  --ghhandle "$GHHANDLE" \
  --description "$DESCRIPTION"
```

Capture the exit code. If non-zero, surface the script's failure context — the script's `die` calls name the failed phase. Do not retry; ask the operator how to proceed.

### Step 7 — Post-bootstrap `repos.yaml` direct commit

The 12-phase script handles `projects.yaml` (fork-divergent — direct commit on the operator's current `aiml0NN` branch). `repos.yaml` is also fork-divergent ([[empty-canonical-repos-yaml]]); the skill commits its entry the same way — same branch, no canonical PR.

In the meta-repo (still in `$META_ROOT`, still on `$CURRENT_BRANCH` from Step 0):

```bash
# Append the repos.yaml entry — rich schema matching the file's actual shape
LOCAL_PATH="/Volumes/AIML01/Users/$USER/claude-code/$GHHANDLE/$NAME"
GITHUB_URL="https://github.com/$GHHANDLE/$NAME"
CLONE_URL="git@github.com:$GHHANDLE/$NAME.git"
NAME="$NAME" GHHANDLE="$GHHANDLE" \
LOCAL_PATH="$LOCAL_PATH" GITHUB_URL="$GITHUB_URL" CLONE_URL="$CLONE_URL" \
DESCRIPTION="$DESCRIPTION" STACK="$STACK" \
yq -i '
  .repos += [{
    "provider": "github",
    "owner": strenv(GHHANDLE),
    "name": strenv(NAME),
    "url": strenv(GITHUB_URL),
    "clone_url": strenv(CLONE_URL),
    "visibility": "private",
    "archived": false,
    "is_template": false,
    "is_fork": false,
    "default_branch": "main",
    "primary_language": (strenv(STACK) | sub("python"; "Python") | sub("bash"; "Shell")),
    "description": strenv(DESCRIPTION),
    "topics": [],
    "kind": "code",
    "clone_state": "cloned",
    "local_path": strenv(LOCAL_PATH),
    "claude_status": "enabled",
    "claude_status_changed_at": null,
    "notes": "bootstrapped via /alemax:new-project"
  }]
' repos.yaml

git add repos.yaml
git commit -m "chore(repos): add $GHHANDLE/$NAME"
REPOS_COMMIT_SHA="$(git rev-parse --short HEAD)"
git push origin "$CURRENT_BRANCH"
echo "repos.yaml entry committed: $REPOS_COMMIT_SHA on $CURRENT_BRANCH"
```

The commit lands on the same `aiml0NN` branch as the `projects.yaml` activation commit emitted by `init-project.sh`. No feature branch is created; no canonical PR is opened.

### Step 8 — Report + next-step command

Print the outcome:

```
✓ Project bootstrapped at /Volumes/AIML01/Users/<u>/claude-code/<handle>/<name>/
✓ GitHub repo: https://github.com/<handle>/<name>
✓ projects.yaml entry committed: <projects-sha> on <aiml0NN>
✓ repos.yaml entry committed: <repos-sha> on <aiml0NN>

Next step:
  cd /Volumes/AIML01/Users/<u>/claude-code/<handle>/<name>/ && claude

(A Claude session can't spawn another Claude session in a different directory;
the operator runs the cd + claude manually.)
```

## Guardrails

- **Never invoke the script without explicit operator confirmation.** Step 5 is non-negotiable.
- **Never bypass validation** in step 3 — even if the operator says "just do it"; the validation messages name fixable problems.
- **Never write `projects.yaml` or `repos.yaml` on canonical.** Both are fork-divergent ([[empty-canonical-projects-yaml]], [[empty-canonical-repos-yaml]]) — entries land as direct commits on the operator's current `aiml0NN` branch. Step 0's branch assertion enforces this upstream.
- **Never auto-invoke `fork-sync.sh`** from Step 1 — refuse + instruct, never sync silently. The operator runs `fork-sync.sh --non-interactive --push` themselves after seeing the refusal.
- **Never touch openspec/** from this skill. That's `/opsx:*` territory.
- **Never `git commit --no-verify`** to bypass the pre-commit hook. If the hook refuses, surface the message + stop.

## Failure modes

| Symptom | Likely cause | Recovery |
|---|---|---|
| Preflight: working tree dirty | meta-repo clone has uncommitted edits | Ask operator to `git stash` or commit before retrying |
| Preflight: SSD not mounted | AIML01 SSD unplugged | Ask operator to plug in or run `init-machine.sh` |
| Preflight: main behind upstream/main | fork hasn't pulled recent canonical updates | Run `./meta/scripts/fork-sync.sh --non-interactive --push` and retry |
| Preflight: aiml0NN behind main | per-drive branch hasn't merged latest fork main | Run `./meta/scripts/fork-sync.sh --non-interactive --push` and retry |
| Preflight: on unexpected branch | current branch is neither `main` nor `aiml0NN` | `git checkout aiml0NN` and retry |
| Validate: name collides | already a project with that name | Suggest a variant; offer to look up the existing one |
| Validate: GitHub repo exists | the handle/name is taken on github.com | Offer to pick a different name |
| init-project.sh fails mid-phase | varies; phase named in error | Surface the failure verbatim; operator decides whether to retry, fix, or abort |
| `git push` to fork fails after repos.yaml commit | ssh / fork access issue | Surface error; the commit is local — operator pushes manually after fixing access |

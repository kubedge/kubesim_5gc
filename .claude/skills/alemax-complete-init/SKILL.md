---
name: alemax-complete-init
description: Project-side completion of a freshly-bootstrapped project — run from the NEW project's own Claude session after `init-project.sh` created and pushed it. Freshness-gated (refuses a long-running project unless --force). Walks: Keychain secrets, `git remote set-head origin --auto`, fresh-bootstrap hygiene (`.python-version`, seed `.claude/settings.local.json` before the first merge — never a tracked `settings.json`, ci.yml stack-trim), go-stack post-generate, verify (+ propose `/doctor`, `/test`, `/security`), guide the first real change → push → merge, then drop the bootstrap nudge. The consumer half of `alemax-new-project`.
license: MIT
compatibility: Requires bash, git, gh. Runs ONLY from a bootstrapped project clone (context: project). Reads `.env.example` + `.meta-version`; drives `bin/set-secret.sh`.
context: project
metadata:
  author: alemax
  version: "1.0"
---

## Wraps

No single shell script. The workflow inspects the project clone's state and walks the operator through the steps that `meta/bootstrap/init-project.sh` deliberately left for the project side — the interactive, project-local, or human-decision work that the meta-repo session cannot perform.

This is the **consumer half** of a producer/consumer pair across the meta↔project boundary: `alemax-new-project` (meta-side, `context: claude-meta-only`) *creates* the project; `alemax-complete-init` (project-side, `context: project`) *finishes* it. It is the first-run analogue of how `alemax-back-burner`/`alemax-front-burner` pair — but the handoff crosses repos, not sessions.

## Why this skill exists

`init-project.sh` does everything it safely can from the meta session: it creates the private repo, wires `origin`, pushes `main`, scaffolds the stack, resolves the lock (`uv lock` / `go mod tidy`), installs + runs pre-commit, and writes the manifest. What it **cannot** do lands here:

- **Secrets** — `bin/set-secret.sh` requires an interactive TTY and the project's own Keychain service (`com.<ghhandle>.<project>`); tooling never writes secret values. The meta session can't supply them.
- **`origin/HEAD`** — bootstrap never runs `git remote set-head origin --auto`, so `/security` (which resolves a base ref via `origin/HEAD`) fails until it's set.
- **The bootstrap nudge** — the shipped `CLAUDE.md` carries a "just bootstrapped, run /opsx:propose" line meant to be deleted after the first real commit.
- **Go-stack post-generate** — `make manifests generate`, renaming the sample API, and the first `docker buildx` image build need the project toolchain and project-domain decisions.

Today all of this is ad-hoc operator memory driven by the printed "Next steps". This skill turns it into a repeatable, state-driven pass.

## Background — the `.meta-version` file in your new repo

This project was generated from a shared toolkit repo (`claude-meta`) that **you do not
have and do not need**. Bootstrap left one trace of it: `.meta-version`, holding a SHA.
You are the first session to see it, so: what it is, and the two ways to break it.

**It is a pointer into that other repository** — the commit of the *toolkit* your files
were generated from. It is not a version of this project. `git show <that-sha>` will
fail here, correctly: the commit is not in your history.

**Its job is to be a merge-base coordinate.** When the toolkit later ships an
improvement — a CI workflow fix, a corrected skill — it reconstructs "what we handed
this project at bootstrap" from that SHA and 3-way merges the change against whatever
you have made of the file since. That is what lets you freely edit a shipped file
without the next update clobbering it.

So, two rules:

- **Never hand-edit or delete `.meta-version`.** A *stale* pin only makes a future merge
  noisier. A *wrong* pin makes the toolkit skip files permanently, silently.
- **Edit shipped files freely** — that is expected and supported. Files under
  `.claude/`, `.github/workflows/`, plus `.gitignore`, `.gitattributes`,
  `.pre-commit-config.yaml`, `.editorconfig` and `bin/` keep receiving updates and your
  edits survive the merge. `CLAUDE.md`, `README.md`, `.env.example`, `.devcontainer/`,
  `openspec/ideas.md` and `pyproject.toml` are **yours alone** from now on — the toolkit
  renders them once, here, and never touches them again.

**How updates will arrive.** Pushed to you, not pulled by you. A meta-side operator
either pushes a `meta-broadcast/*` branch to *this* repo's origin and drops a
`.local/HANDOFF.md`, or prepares a local `claude-meta-update` branch. Either way you
then run `/alemax:complete-update`, whose own Background section explains the shapes.
You never clone the toolkit — if something is missing, it is re-broadcast to you.

## Behavior overview

0. **Step 0 — Context + freshness check.** Refuse if run from the meta-repo (this skill is `context: project`). Confirm a bootstrapped project clone (`.meta-version` present, `origin` is not canonical claude-meta) AND that it is **fresh** — refuse an established (long-running) clone unless `--force`, so a mis-invocation can't clobber settings the project now owns.
1. **Phase 1 — Detect stack + state.** pyproject.toml / go.mod / bin+bats. Read `.meta-version`.
2. **Phase 2 — Keychain secrets.** Diff `.env.example` keys against what's set (`bin/set-secret.sh --list`); offer `bin/set-secret.sh --bootstrap` (interactive).
3. **Phase 3 — `origin/HEAD`.** If unset, run `git remote set-head origin --auto`.
4. **Phase 4 — GH Actions secrets (advisory).** If CI consumes secrets, point at the meta-side `sync-secrets-to-gh.sh` (runs from the meta clone).
5. **Phase 5 — Fresh-bootstrap hygiene.** Detect + offer fixes for gaps a fresh bootstrap leaves (from smoke-test-3): a missing `.python-version`; a missing `.claude/settings.local.json` (the operator-local, gitignored grant store — seed the `/alemax:*` gh verbs **before the first merge** so `gh pr merge` doesn't hit a permission wall; **never** a tracked `settings.json`); and non-applicable cross-stack `ci.yml` jobs.
6. **Phase 6 — Go-stack post-generate (go only).** Guided checklist: `make manifests generate`, rename sample API, first image build.
7. **Phase 7 — Verify.** pre-commit installed; run the project's tests; **propose the built-in health checks `/doctor`, `/test`, `/security`**; best-effort CI status via `gh run list`.
8. **Phase 8 — First real change (exercise the flow).** Guide the operator's first change (via `/opsx:propose`, or a small `greet()`) → commit → push → open PR → **merge**. The seeded `.claude/settings.local.json` from Phase 5 is what makes that merge work — this is the step where the whole flow (and the gh permission wall) actually surfaces.
9. **Phase 9 — Bootstrap nudge removal.** **Only after** a first real change has been created, pushed, and merged (Phase 8), offer to drop the `CLAUDE.md` "just bootstrapped" nudge. Leave it in place until then — it's still doing its job.
10. **Phase 10 — Summary + next step.** Report what was completed / still pending; point at `/opsx:propose` for the next change.

Every mutating step confirms first. Steps whose input is human-owned (secret values, API rename) are guided, not automated.

## Steps

### Step 0 — Context check (refuse on meta-repo)

```bash
CURRENT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$CURRENT_ROOT" ] || { echo "Error: not inside a git repository."; exit 1; }
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
# This skill runs from a PROJECT clone, never the meta-repo.
if [[ "$ORIGIN_URL" == *"claude-meta"* && "$CURRENT_ROOT" == *"/claude-meta" ]]; then
  echo "ERROR: alemax-complete-init is context: project — run it from a bootstrapped PROJECT clone, not the meta-repo." >&2
  echo "  You appear to be in the claude-meta meta-repo ($CURRENT_ROOT)." >&2
  echo "  To bootstrap a NEW project, use /alemax:new-project from here instead." >&2
  exit 1
fi
if [[ ! -f "$CURRENT_ROOT/.meta-version" ]]; then
  echo "ERROR: no .meta-version at $CURRENT_ROOT — this does not look like a claude-meta-bootstrapped project." >&2
  echo "  If this is a repo you want to retrofit, that's a meta-side operation (retrofit-project.sh)." >&2
  exit 1
fi
PROJECT_ROOT="$CURRENT_ROOT"
DRY_RUN="${DRY_RUN:-0}"   # set 1 if --dry-run passed
FORCE="${FORCE:-0}"       # set 1 if --force passed

# Freshness gate — complete-init FINISHES a fresh bootstrap. On a long-running
# project its mutating steps (.python-version, .claude/settings.local.json,
# nudge removal, origin/HEAD, ci.yml trim) can clobber choices the project now
# owns. If the skill was invoked by mistake on an established clone, REFUSE.
# Signal: commit count well past a fresh bootstrap (a fresh clone is 1 commit
# plus maybe a little first-session work). Escape hatch: --force.
COMMITS="$(git -C "$PROJECT_ROOT" rev-list --count HEAD 2>/dev/null || echo 0)"
FRESH_MAX="${COMPLETE_INIT_FRESH_MAX:-10}"
if [ "$COMMITS" -gt "$FRESH_MAX" ] && [ "$FORCE" -ne 1 ]; then
  echo "ERROR: this clone has $COMMITS commits — it looks like an established project, not a fresh bootstrap." >&2
  echo "  complete-init finishes a FRESH bootstrap; on a long-running project its mutating steps can clobber" >&2
  echo "  choices the project now owns (.python-version, .claude/settings.local.json, the CLAUDE.md nudge, ci.yml)." >&2
  echo "  If you genuinely mean to run it here, re-run with --force." >&2
  exit 1
fi
```

Parse `--dry-run` and `--force` from args. `--dry-run`: every mutating step describes-only. `--force`: bypass the freshness gate above (nothing else). The freshness gate is the primary guard against a mis-invocation on a long-running project; the per-step confirms below are the second line of defense.

### Phase 1 — Detect stack + state

```bash
STACK="unknown"
[ -f "$PROJECT_ROOT/pyproject.toml" ] && STACK="python"
[ -f "$PROJECT_ROOT/go.mod" ] && STACK="go"
[ "$STACK" = "unknown" ] && { [ -d "$PROJECT_ROOT/bin" ] || ls "$PROJECT_ROOT"/tests/*.bats >/dev/null 2>&1; } && STACK="bash"
GHHANDLE="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null | sed -E 's#.*[:/]([^/]+)/[^/]+(\.git)?$#\1#' || true)"
PROJECT_NAME="$(basename "$PROJECT_ROOT")"
COMMITS="$(git -C "$PROJECT_ROOT" rev-list --count HEAD 2>/dev/null || echo 0)"
```

Report the detected stack, service name (`com.$GHHANDLE.$PROJECT_NAME`), and commit count so the operator sees where the project is.

### Phase 2 — Keychain secrets

```bash
if [ -f "$PROJECT_ROOT/bin/set-secret.sh" ]; then
  bash "$PROJECT_ROOT/bin/set-secret.sh" --list   # shows set vs missing per .env.example key
fi
```

- If any key is `missing`, offer to run `bin/set-secret.sh --bootstrap` (walks each unset key, prompts for hidden input, stores in Keychain). This is interactive — the operator types the values; the skill never sees or logs them.
- If `.env.example` has no real keys yet (only the shipped example comments), note that the operator should declare the project's actual keys first, then re-run.
- Skip silently (report "no secrets declared") if `.env.example` is effectively empty.

### Phase 3 — `origin/HEAD`

```bash
if ! git -C "$PROJECT_ROOT" symbolic-ref --quiet refs/remotes/origin/HEAD >/dev/null 2>&1; then
  echo "origin/HEAD is not set — /security's base-ref resolution needs it."
  # On confirm (and not DRY_RUN):
  git -C "$PROJECT_ROOT" remote set-head origin --auto
fi
```

Report set/already-set. This is the fix for the recurring `/security` "ambiguous origin/HEAD" failure.

### Phase 4 — GitHub Actions secrets (advisory)

If the project's CI consumes any Keychain secret (i.e. `.env.example` declares keys that CI needs), remind the operator that pushing them to GitHub Actions is a **meta-side** step:

```
Run from your claude-meta clone (not here):
  ./meta/bin/sync-secrets-to-gh.sh --project <name>
```

Advisory only — the bridge script lives meta-side and reads the now-populated project Keychain.

### Phase 5 — Fresh-bootstrap hygiene

Gaps a fresh bootstrap leaves that only surface project-side (found by smoke-test-3). Each is a detect + an offered fix, confirmed before writing; skip cleanly if already present.

```bash
# a) .python-version — pin the interpreter so the declared lint/type target
#    (pyproject requires-python + ruff/mypy target) matches the uv-resolved
#    local AND CI Python. Without it uv resolves latest (e.g. 3.14.x) in both
#    places while mypy type-checks as 3.13 — a silent drift.
if [ -f "$PROJECT_ROOT/pyproject.toml" ] && [ ! -f "$PROJECT_ROOT/.python-version" ]; then
  want="$(grep -oE 'requires-python *= *"[^"]+"' "$PROJECT_ROOT/pyproject.toml" | grep -oE '[0-9]+\.[0-9]+' | head -1)"
  echo "GAP: no .python-version; declared target is ${want:-3.13}. Offer: echo ${want:-3.13} > .python-version"
fi

# b) .claude/settings.local.json — the operator-local, gitignored grant store
#    every project uses (Claude Code persists session grants here). Do NOT
#    create a tracked .claude/settings.json — that's a repo-policy choice these
#    projects don't make (test-3's own session closed the "check in a baseline
#    settings.json" PR). Seeding settings.local.json with the /alemax:* gh verbs
#    up front avoids the mid-workflow permission wall (test-3 hit it when
#    /alemax:dependabot-merge-all's `gh pr merge` was denied after the batch had
#    already started). It must be gitignored FIRST so the grants never commit.
if ! grep -qE '(^|/)\.claude/settings\.local\.json' "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
  echo "GAP: .claude/settings.local.json is not gitignored — add the rule before seeding (grants must never be committed)."
fi
if [ ! -f "$PROJECT_ROOT/.claude/settings.local.json" ]; then
  echo "GAP: no .claude/settings.local.json; the first /alemax:* gh action will prompt (or wall mid-workflow)."
  echo "  Offer to seed it (operator-local, gitignored) with an allow-list for: gh pr merge/create/comment/close/view/diff/list/checks, gh run list/view, gh api."
fi

# c) cross-stack ci.yml jobs — the universal ci.yml carries every stack's jobs
#    (runtime-gated), but Dependabot bumps their actions statically. A fresh repo
#    bootstrapped AFTER the stack-trim fix won't have this (the scaffolder trims
#    ci.yml at bootstrap); this catches a fresh clone bootstrapped before it.
CI="$PROJECT_ROOT/.github/workflows/ci.yml"
if [ ! -f "$PROJECT_ROOT/go.mod" ] && [ -f "$CI" ] && yq -e '.jobs["go-build"]' "$CI" >/dev/null 2>&1; then
  echo "GAP: non-go repo still carries the go-* ci.yml jobs (dead Dependabot bumps for setup-go/golangci)."
  echo "  Offer: yq -i 'del(.jobs.go-build, .jobs.go-vet, .jobs.go-test, .jobs.golangci-lint)' \"$CI\""
fi
```

For **(a)**, write `.python-version` with the declared target (confirm first). For **(b)**, ensure `.claude/settings.local.json` is gitignored, then offer to **seed it** (operator-local, never a tracked `settings.json`) with the `/alemax:*` gh allow-list. For **(c)**, offer the `yq` trim of the non-applicable stack jobs. All are safe project-local writes — and the freshness gate in Step 0 keeps them from ever touching a long-running project by mistake.

### Phase 6 — Go-stack post-generate (go only)

Skip entirely unless `STACK == go`. Present as a guided checklist (these need the operator's tools + domain decisions; the skill runs what's safe and explains the rest):

- **`make manifests generate`** — regenerates CRDs + DeepCopy via `controller-gen`. Bootstrap ships a hand-written `zz_generated.deepcopy.go` stopgap; run this once the operator has `controller-gen`/`operator-sdk` installed. Offer to run it if `make` + the tool are present.
- **Rename the sample API** — `api/v1alpha1/sample_types.go` (Kind `Sample`, group `apps.<ghhandle>.io`) to the real resource, then re-run `make manifests generate`. Human domain modeling — guide, don't automate.
- **First image build** — `make docker-build` / `docker-buildx` / `docker-push` needs a working on-volume `docker buildx` daemon (see the meta-repo's HOW-TO-INSTALL-DOCKER). Advisory.

### Phase 7 — Verify

- Confirm pre-commit hooks are installed (`.git/hooks/pre-commit` exists); if not, `pre-commit install`.
- Run the project's tests: `uv run pytest` (python) / `bats tests/` (bash) / `go test ./...` (go). Report pass/fail; do not auto-fix.
- **Propose the built-in health checks** (proposals, not auto-runs): `/doctor` (Claude Code environment/setup health — the same check that surfaced auto-mode + settings issues in the meta-repo), `/test` (the scaffolded test command), and `/security` (delegates to the built-in `/security-review`; relies on the `origin/HEAD` set in Phase 3). Suggest the operator run these before shipping.
- Best-effort CI: `gh run list --limit 3` to show whether the last push's CI is green / red / blocked (org Actions-billing walls show as blocked, not a real failure — see the meta-repo's feedback note on admin-merge).

### Phase 8 — First real change (exercise the flow)

The `CLAUDE.md` nudge asks the operator to make their first real change. Guide that here — it's also where the end-to-end flow (and the `gh pr merge` permission wall) actually surfaces, so it belongs in "finish the bootstrap":

- Prompt the operator to make a small first change — via `/opsx:propose`, or directly (e.g. a `greet()` function + its test). The skill does **not** invent the change; the operator decides what it is.
- Commit it, push, open a PR, and **merge** it. The `.claude/settings.local.json` seeded in Phase 5 is what lets `gh pr merge` (and the `/alemax:dependabot-merge*` skills) run without hitting the permission wall — which is why Phase 5 comes first.
- Confirm CI went green on the merge (`gh run list`).
- If the operator isn't ready to make a real change yet, skip this and Phase 9 and leave the nudge in place.

### Phase 9 — Bootstrap nudge removal

**Only after** a first real change has been created, pushed, and **merged** (Phase 8): the `CLAUDE.md` "> Just bootstrapped … delete this note after your first real commit" block has done its job — offer to remove it (confirm first; not on `DRY_RUN`). If only the bootstrap commit exists / no real change has landed, do NOT remove it — the nudge should keep prompting until the first change ships.

### Phase 10 — Summary + next step

Print a compact table: each phase → done / skipped / still-pending (with the exact command to finish anything pending). Point at `/opsx:propose` for the next change.

## Edge cases

- **Run from the meta-repo** — refused in Step 0 with the `/alemax:new-project` hint.
- **Established / long-running project** (commit count > `COMPLETE_INIT_FRESH_MAX`, default 10) — refused in Step 0 unless `--force`. This is the guard against a mistaken invocation mutating a project that now owns its own `.python-version` / `.claude/settings.local.json` / `ci.yml`.
- **Not a bootstrapped project** (no `.meta-version`) — refused with the retrofit hint.
- **`bin/set-secret.sh` absent** (older bootstrap) — skip Phase 2 with a note.
- **No controlling TTY** (headless) — Phase 2 can't prompt for secrets; report and skip, leaving them pending.
- **Non-TTY / CI run of the skill itself** — treat as `--dry-run`: enumerate, mutate nothing.

## system-path-rule

This skill operates exclusively under the current project clone (its `bin/`, `.env.example`, `.git/`, `CLAUDE.md`) and the macOS Keychain via the `security` command (no filesystem path). No macOS-system-rooted paths are touched.

## Cross-links

- `.claude/skills/alemax-new-project/SKILL.md` — meta-side producer that creates the project this skill finishes.
- `.claude/skills/alemax-complete-update/SKILL.md` — sibling: finishes a template *update* from the project side.
- `openspec/specs/project-side-completion/spec.md` — capability spec (the project-side completion contract).
- `openspec/specs/alemax-skills/spec.md` — family conventions + `context` enforcement (this is the first `context: project` skill).

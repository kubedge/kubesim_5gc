---
name: alemax-complete-update
description: Project-side completion of a meta update — run from the project's own Claude session. Reads the meta side's `.local/HANDOFF.md` (or `.local/update-todo.md`) to learn what to check, finds the corresponding update branch it names (locally in a nearby git worktree, or remotely on the project's origin), and applies it onto `main` — cherry-picking a broadcast (shaped `base@pin <- update@new`) so any 3-way conflict surfaces in the project's own checkout for this session to resolve, or merging a sync `--no-ff`. Then it finishes what the meta side can't: resolve those conflicts with local context, re-lock deps, apply the migration/checks the handoff lists, run the project's tests, push, verify CI. The customer never clones the meta-repo — the class-M/P content is in the branch, the briefing is in the handoff. Consumer half of `alemax-update-skills`.
license: MIT
compatibility: Requires bash, git, gh. Runs ONLY from a project clone (context: project). Never clones or reaches into the meta-repo — works from the pushed branch + the handoff note.
context: project
metadata:
  author: alemax
  version: "1.1"
---

## Wraps

No new machinery — this consumes what the **validated** meta-side scripts produced. The meta side (`alemax-update-skills` → `broadcast-update.sh`, worktree-isolated) builds a `meta-broadcast/<slug>` branch shaped `[base @ the project's pin] <- [update @ meta's current version]`, pushes it, and leaves a `.local/HANDOFF.md` briefing. **A broadcast is delivered UNresolved on purpose:** meta ships the base+update materials but does not merge them, because it cannot know why the project edited a class-M file. This skill, run from the project session, **cherry-picks the update onto `main` so any 3-way surfaces in the project's OWN checkout**, where this session resolves it with local context; then it does the project-local bits. (A **sync** branch, `claude-meta-update`, is the exception — it was reconciled meta-side against the orphan base and is merged, not cherry-picked.)

Three hard rules this skill honors:

1. **The customer never clones the meta-repo.** Everything needed is in the pushed branch (the class-M/P content) and the `.local/HANDOFF.md` briefing. No meta clone, no reaching into `meta/` — if the content isn't in the branch, that's a meta-side re-broadcast, not something the project fetches from meta by hand.
2. **Resolve the merge where the context is.** For a **sync**, the class-aware 3-way already ran meta-side; just merge the branch. For a **broadcast**, meta deliberately did NOT resolve — it shipped `base@pin <- update@new`, and THIS session cherry-picks it and resolves any 3-way locally, because only here is it known why a class-M file was edited. Then run the project-local checks the handoff lists.
3. **The branch already carries the correct pin — apply it, don't second-guess it.** A **sync** branch carries `.meta-version` = the target meta SHA, so merging it advances the pin automatically. A **broadcast** advances it only when the delivery covered the **complete class-M set**; `broadcast-update.sh` computes that set from `scaffolding/propagation-policy.yaml` at run time and stamps only then, and a partial delivery ships the pin unchanged so the path drops out of the patch entirely. Either way the right value is already in the branch. **If `.meta-version` moved after a broadcast, that is a complete delivery behaving correctly — do not revert it.** Reverting writes a stale pin, and a wrong pin is worse than a stale one: it makes the pull path skip the undelivered paths permanently.

## Background — what you are looking at, and why it looks strange

**Read this before Phase 1.** You are in a project clone with no access to the
`claude-meta` repo, and two things in front of you make no sense without it: a
`.meta-version` file holding a SHA you cannot resolve, and a delivered branch that
shares no history with your `main`. Both are deliberate. This section is the only
place that explains them, because you have no other source.

### `.meta-version` is a pointer into a *different* repository

Your project was generated from a shared toolkit repo (`claude-meta`). The SHA in
`.meta-version` names a commit **of that repo** — the version of the toolkit you were
generated from, or last updated to.

- `git show <that-sha>` **fails here, and that is correct.** The commit is not in your
  history. `.meta-version` is not a version of *your* project, not a tag, not a release.
- It is a **merge-base coordinate**. It is how meta reconstructs "what we handed you last
  time" so your local edits can be reconciled by a real 3-way merge instead of being
  overwritten by a copy.
- Therefore: never hand-edit it, never "fix" it to something that looks nicer, never
  delete it. A *stale* pin only makes future merges noisier; a *wrong* pin makes meta
  skip files permanently, and the damage is silent.

### Why the delivered branch has no shared history with your `main`

A broadcast arrives as **two commits on an orphan branch**:

```
commit 2   "<message> (meta-broadcast update)"      = what meta ships NOW
commit 1   "meta-broadcast base @ <your pin>"       = what meta gave you AT your pin
```

Cherry-picking commit 2 makes git use commit 1 as the **merge base**, with your `main`
as "ours" — a genuine 3-way merge. That is the entire mechanism, and it is why:

- **Cherry-pick it. Never `git merge` it.** A merge takes meta's tree wholesale and
  silently drops your customizations. Don't rebase it onto `main`, don't squash it,
  don't reach for `-X theirs`.
- **Some files arrive as *adds* rather than edits.** Commit 1 deliberately omits any
  path you don't already have, so a file you never received lands as a clean add instead
  of a `modify/delete` conflict.

There is a second, rarer shape: a **sync** branch named `claude-meta-update`. It
descends normally from your `main`, the 3-way already ran on the meta side, and it
carries the new pin. That one you **merge** `--no-ff`. Phase 3 tells the two apart by
branch name; everything else in this section applies to both.

### Class M vs class P — why some of your files are never touched

Meta classifies everything it ships. **Class M** (merge-propagated) keeps flowing to
you and your edits survive via the 3-way: `.claude/**`, `.github/workflows/**`,
`.gitignore`, `.gitattributes`, `.pre-commit-config.yaml`, `.editorconfig`, `bin/**`.
**Class P** is yours permanently and meta never ships it again: `CLAUDE.md`,
`README.md`, `.env.example`, `.devcontainer/`, `openspec/ideas.md`, `pyproject.toml`.
If an update didn't touch your `README.md`, that is the design, not a miss.

### A conflict here is a question, not a failure

Meta cannot know *why* you edited a class-M file, so it ships the raw materials
**unresolved on purpose** and stops. The conflict is the delivery asking the one
question only this session can answer: keep the project's customization **and** fold in
meta's change. Resolving wholesale toward meta is how a project silently loses local
work — and it looks especially tempting when the conflict is one small hunk.

### The `../<project>-claude-meta` worktree

Despite the name it is **not** a meta clone — it is a `git worktree` of *your own repo*,
checked out at the delivered commit, carrying the delivered files. On a first update it
is also the only place this skill's own body exists. Don't remove it until the update is
complete; do remove it afterwards.

### Never do these, however reasonable they look

- clone or fetch from `claude-meta` — you don't need it, and it is not yours to reach
  into. If content is missing, ask the meta side for a re-broadcast.
- hand-edit `.meta-version`, in either direction
- `git merge` a `meta-broadcast/*` branch
- delete the staged worktree before finishing
- resolve conflicts toward meta without reading them

## Behavior overview

0. **Step 0 — Context check.** Refuse if run from the meta-repo (`context: project`).
1. **Phase 1 — Read the handoff.** Read `.local/HANDOFF.md` (or `.local/update-todo.md`): it says what this update is, names the branch, lists what to check and any migration notes. This drives every later phase — the skill does not guess.
2. **Phase 2 — Find the branch the handoff names.** Locate it without cloning meta: a local ref / **nearby git worktree** first, else fetch it **remotely** from the project's `origin`. (Same local-or-remote lookup the broadcast already uses for files.)
3. **Phase 3 — Apply the update onto `main`.** Cherry-pick a broadcast (`meta-broadcast/*`, orphan `base<-update`) so any 3-way surfaces in YOUR checkout; merge a sync (`claude-meta-update`) `--no-ff`. Resolve conflicts here — meta never resolves them for you.
4. **Phase 4 — Complete per the handoff.** Run exactly what the handoff's checklist lists — re-lock (`uv lock` / `go mod tidy`), apply any migration delta it names, and the checks it calls for. Use the project's own toolchain; don't invent steps the handoff didn't ask for.
5. **Phase 5 — Run project checks.** pre-commit + tests against the merged tree.
6. **Phase 6 — Push + verify CI + clean up.** Push `main`, check CI, delete the merged branch, and clear/annotate the handoff.

Every mutating step confirms first.

## Steps

### Step 0 — Context check (refuse on meta-repo)

```bash
CURRENT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$CURRENT_ROOT" ] || { echo "Error: not inside a git repository."; exit 1; }
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ "$ORIGIN_URL" == *"claude-meta"* && "$CURRENT_ROOT" == *"/claude-meta" ]]; then
  echo "ERROR: alemax-complete-update is context: project — run it from the PROJECT clone, not the meta-repo." >&2
  echo "  To PUSH an update from the meta-repo, use /alemax:update-skills." >&2
  exit 1
fi
PROJECT_ROOT="$CURRENT_ROOT"
DRY_RUN="${DRY_RUN:-0}"
HANDOFF="$PROJECT_ROOT/.local/HANDOFF.md"
NOTE="$PROJECT_ROOT/.local/update-todo.md"
```

### Phase 1 — Read the handoff (what to check)

The handoff is the meta side's briefing — **the authoritative "what to check" list**, so the skill follows it instead of guessing.

```bash
BRIEF=""
[ -f "$HANDOFF" ] && BRIEF="$HANDOFF"
[ -z "$BRIEF" ] && [ -f "$NOTE" ] && BRIEF="$NOTE"
if [ -n "$BRIEF" ]; then
  echo "Handoff: $BRIEF"
  cat "$BRIEF"                      # its checklist + migration notes drive Phases 3-5
  # the note names the branch (meta_to / a meta-broadcast/<slug> ref) + what to verify.
else
  echo "No .local/HANDOFF.md or update-todo.md — will still look for an update branch (Phase 2)"
  echo "and probe for local class-M gaps (Phase 4); report 'already current' only if none."
fi
```

Pull the **branch name** and the **checklist** out of the handoff; both feed the next phases. If there's no handoff, continue — Phase 2 can still discover a branch, and Phase 4 still probes.

### Phase 2 — Find the branch the handoff names (no meta clone)

Locate the branch **without cloning meta** — the class-M/P content is already in it. Local first (a nearby worktree/ref), then remote:

```bash
UPDATE_REF=""
# 1) Local: a ref already in this repo (e.g. claude-meta-update from a sync, or a
#    branch fetched from a nearby meta/project worktree the operator names via META_SRC).
for cand in claude-meta-update ${HANDOFF_BRANCH:-}; do
  [ -n "$cand" ] && git -C "$PROJECT_ROOT" rev-parse --verify --quiet "$cand" >/dev/null && UPDATE_REF="$cand" && break
done
if [ -z "$UPDATE_REF" ] && [ -n "${META_SRC:-}" ]; then
  git -C "$PROJECT_ROOT" fetch "$META_SRC" 'refs/heads/meta-broadcast/*:refs/remotes/metasrc/meta-broadcast/*' --quiet || true
  UPDATE_REF="$(git -C "$PROJECT_ROOT" for-each-ref --format='%(refname:short)' 'refs/remotes/metasrc/meta-broadcast/*' | head -1)"
fi
# 2) Remote: the branch pushed to the project's own origin.
if [ -z "$UPDATE_REF" ]; then
  git -C "$PROJECT_ROOT" fetch origin --quiet || true
  UPDATE_REF="$(git -C "$PROJECT_ROOT" for-each-ref --format='%(refname:short)' 'refs/remotes/origin/meta-broadcast/*' | head -1)"
fi
[ -n "$UPDATE_REF" ] && echo "Update branch: $UPDATE_REF" || echo "No update branch found — nothing to merge (Phase 3 skipped)."
```

Prefer the branch the handoff names; if several `meta-broadcast/*` exist, list them and let the operator pick.

### Phase 3 — Apply the update onto `main` (cherry-pick a broadcast, merge a sync)

Skip if Phase 2 found none. **How you apply it depends on the delivery shape** — and the difference is deliberate, so a genuine 3-way conflict surfaces HERE, in your checkout, where this session knows why a file was changed. Meta cannot know that, so it never resolves conflicts for you.

- **Broadcast** (`meta-broadcast/*`): the branch is `[base @ your pin] <- [update @ meta current]`. **Cherry-pick the update commit** (the branch tip) onto `main`. Git uses the base-@-pin commit (the tip's parent) as the 3-way merge base: a file you never customised applies/adds cleanly; a file you genuinely edited surfaces real conflict markers for you to resolve. Do NOT `git merge` it — that takes meta's version wholesale and silently drops your edits.
- **Sync** (`claude-meta-update`): that branch descends from `main` and carries the new `.meta-version`; **merge it** `--no-ff` as before (which advances the pin automatically).

**Phase 3a — clear the bootstrap collision FIRST.** On a project's *first* update this
skill was not installed, so the operator copied it out of the staged worktree per the
handoff. Those copied files are **untracked**, and the delivery contains the same paths
— so git refuses the cherry-pick with *"untracked working tree files would be
overwritten by merge."* Commit them before applying anything. This is intrinsic to the
bootstrap: the skill being installed is itself part of the payload.

```bash
git -C "$PROJECT_ROOT" checkout main   # this session is the actor — conflicts landing in main are wanted

# 3a — track any untracked bootstrap copies of this skill + its command wrapper.
BOOTSTRAP=(.claude/skills/alemax-complete-update .claude/commands/alemax/complete-update.md)
UNTRACKED=()
for b in "${BOOTSTRAP[@]}"; do
  while IFS= read -r u; do [[ -n "$u" ]] && UNTRACKED+=("$u"); done \
    < <(git -C "$PROJECT_ROOT" ls-files --others --exclude-standard -- "$b")
done
if [[ ${#UNTRACKED[@]} -gt 0 ]]; then
  git -C "$PROJECT_ROOT" add -- "${UNTRACKED[@]}"
  git -C "$PROJECT_ROOT" commit -m "chore(claude): bootstrap /alemax:complete-update from the staged worktree"
fi

# 3b — apply.
case "$UPDATE_REF" in
  *meta-broadcast/*) git -C "$PROJECT_ROOT" cherry-pick "$UPDATE_REF" ;;   # tip = update; parent = base @ pin
  *)                 git -C "$PROJECT_ROOT" merge --no-ff --no-edit "$UPDATE_REF" ;;
esac
```

If the cherry-pick still aborts on untracked files, the fix is to **track** the offending
paths, never to delete them and never to force the pick.

- **Clean:** proceed to Phase 4.
- **Conflict:** git left real 3-way markers in the affected files. Resolve each — keep the project's customization AND fold in the meta update; you have the local context to judge — then `git add` the resolved files and continue: `git cherry-pick --continue` (broadcast) or `git commit` (sync merge). Never auto-resolve substantive conflicts: doing that judgement here, not meta-side, is the entire point.

### Phase 3c — Re-trim `ci.yml` to this project's stack

Meta ships **one universal `ci.yml`** with jobs for every stack, runtime-gated on
`go.mod` / `pyproject.toml`. The gate stops them *running*; it does **not** stop
Dependabot, which parses the workflow **statically** and opens bump PRs for
`actions/setup-go` or `astral-sh/setup-uv` in a repo that will never run them.

Bootstrap trims the jobs this stack doesn't need — but only the ones that existed
*then*. When meta later adds a job for another stack, the 3-way correctly delivers it
here as new content. So after any delivery, re-assert the trim.

**Do this once and it stays done.** The next delivery's 3-way sees the base carrying
those jobs, your `main` having deleted them, and meta not having touched them — so the
deletion wins with no conflict. This is why the trim belongs in the project's history
and **not** in the delivered payload: a payload trimmed by meta would make every
project's base differ, and meta would be deciding a question the project owns.

```bash
cd "$PROJECT_ROOT"
# stack from what is actually on disk, not from the manifest
if   [ -f pyproject.toml ]; then STACK=python
elif [ -f go.mod ];        then STACK=go
else                            STACK=bash; fi

CI=.github/workflows/ci.yml
case "$STACK" in
  python) DEL='del(.jobs.go-build, .jobs.go-vet, .jobs.go-test, .jobs.golangci-lint)' ;;
  go)     DEL='del(.jobs.type-check)' ;;
  bash)   DEL='del(.jobs.go-build, .jobs.go-vet, .jobs.go-test, .jobs.golangci-lint, .jobs.type-check)' ;;
esac
[ -f "$CI" ] && yq -i "$DEL" "$CI"      # yq preserves `on:`; removed jobs only `needs: detect`

# dependabot: the stack's own ecosystem, added only if absent
DEP=.github/dependabot.yml
case "$STACK" in python) ECO=uv ;; go) ECO=gomod ;; *) ECO="" ;; esac
if [ -n "$ECO" ] && [ -f "$DEP" ] && ! yq -e ".updates[] | select(.package-ecosystem == \"$ECO\")" "$DEP" >/dev/null 2>&1; then
  printf '\n  - package-ecosystem: "%s"\n    directory: "/"\n    schedule:\n      interval: "weekly"\n    open-pull-requests-limit: 5\n' "$ECO" >> "$DEP"
fi

git diff --quiet -- "$CI" "$DEP" || {
  git add -- "$CI" "$DEP"
  git commit -m "fix(ci): re-trim the shipped workflow to the $STACK stack"
}
```

Never add `pip` for a uv-managed project: it raises the `pyproject.toml` specifier
without touching `uv.lock`, so a bump merges green while CI still tests the locked
versions. Never add `npm` without a `package.json` — it red-fails every run.

### Phase 4 — Complete per the handoff

Do exactly what the handoff's checklist lists — no more, no less. Typical items it names:

- **Re-lock** (project-local; the branch can't carry a lock resolved against the project's own graph):
  ```bash
  git -C "$PROJECT_ROOT" diff --name-only HEAD@{1} HEAD 2>/dev/null | grep -q '^pyproject\.toml$' && ( cd "$PROJECT_ROOT" && uv lock && uv sync --locked )
  git -C "$PROJECT_ROOT" diff --name-only HEAD@{1} HEAD 2>/dev/null | grep -q '^go\.mod$' && ( cd "$PROJECT_ROOT" && go mod tidy )
  ```
- **Migration deltas** the handoff spells out (e.g. add the stack `dependabot.yml` `uv`/`gomod` block a stack-agnostic delta can't know).
- Any repo-specific check the handoff calls for.

If the handoff flags a still-missing class-M item (e.g. a `/alemax:*` command whose skill body the branch didn't carry), it's a meta-side re-broadcast — note it, don't fetch from meta by hand.

### Phase 5 — Run the project's own checks

```bash
( cd "$PROJECT_ROOT" && { command -v pre-commit >/dev/null && pre-commit run --all-files || uv run pre-commit run --all-files; } ) || echo "pre-commit reported issues — review."
[ -f "$PROJECT_ROOT/pyproject.toml" ] && ( cd "$PROJECT_ROOT" && uv run pytest -q )
[ -f "$PROJECT_ROOT/go.mod" ] && ( cd "$PROJECT_ROOT" && go test ./... )
ls "$PROJECT_ROOT"/tests/*.bats >/dev/null 2>&1 && ( cd "$PROJECT_ROOT" && bats tests/ )
```

### Phase 6 — Push + verify CI + clean up

Push `main`, `gh run list --limit 3` to confirm CI (blocked ≠ failed on billing-capped orgs), delete the merged branch (local + `origin/meta-broadcast/*`), and clear the handoff (or rewrite it with only unfinished items). Print a compact summary + the exact `/alemax:update-skills` request for anything the meta side must re-broadcast.

## Edge cases

- **Run from the meta-repo** — refused in Step 0.
- **Handoff present, branch missing** — the push didn't land / was cleaned; ask the meta side to re-run `/alemax:update-skills`. Do not clone meta to reconstruct it.
- **Branch present, no handoff** — merge it, then follow Phase 4's minimal probes; report what you did.
- **Neither** — nothing to do; report "already current".
- **Merge conflict** — Phase 3 guides resolution; never auto-resolved.
- **Offline / private origin** — set `META_SRC=<path to a nearby worktree/clone holding the branch>`; Phase 2 fetches from there. Still no meta clone required for content — only the branch.
- **Non-TTY / CI run** — treat as `--dry-run`: enumerate, mutate nothing.

## system-path-rule

This skill operates exclusively under the current project clone (its manifests, lockfiles, `.github/`, `.claude/`, `.git/`, and `.local/{HANDOFF.md,update-todo.md}`). No macOS-system-rooted paths are touched.

## Cross-links

- `.claude/skills/alemax-update-skills/SKILL.md` — meta-side producer: worktree build → push `meta-broadcast/*` branch + write the handoff.
- `meta/scripts/broadcast-update.sh` / `meta/bootstrap/lib/propagation.sh` — the validated engine that reconciles the branch (runs meta-side).
- `meta/scripts/sync-from-meta.sh` / `finalize-sync.sh` — the pull path (local `claude-meta-update` branch + `.local/update-todo.md`).
- `.claude/skills/alemax-complete-init/SKILL.md` — sibling: finishes a *bootstrap* from the project side.
- `openspec/specs/project-side-completion/spec.md` — capability spec.

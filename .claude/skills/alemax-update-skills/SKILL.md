---
name: alemax-update-skills
description: Meta-side broadcast of the class-M artifact set to the whole fleet — the fix for the "delivery, not authorship" gap (existing projects silently run stale `.claude/` skills/commands and old CI templates because class-M updates only arrive on a manual sync). Wraps the multi-path `broadcast-update.sh`: defaults to the COMPLETE class-M set computed from propagation-policy.yaml (or a `--since <ref>` delta / explicit `--path`), stages one unresolved `[base <- update]` branch per active project plus a persistent `../<project>-claude-meta` worktree and a short handoff, and opens NO PR. Meta does not merge and does not resolve — every delivered project finishes from its own session via `/alemax:complete-update`.
license: MIT
compatibility: Requires bash, git, gh, yq. Runs from the operator's FORK clone on its `aiml0NN` branch (context: claude-meta-only) — `projects.yaml` must be populated (canonical's is empty). Wraps `meta/scripts/broadcast-update.sh`.
context: claude-meta-only
metadata:
  author: alemax
  version: "1.0"
---

## Wraps

`meta/scripts/broadcast-update.sh` (multi-path). This skill does NOT re-implement the delivery. The script stages an unresolved `[base @ pin] <- [update @ current]` orphan pair per project, leaves a persistent `../<project>-claude-meta` worktree carrying the payload, writes a short `.local/HANDOFF.md`, refuses class-P paths, and **opens no PR** (an orphan pair shares no history with `main`). **Meta does not merge and does not skip a project on conflict** — the project's own session cherry-picks and resolves, because only it knows *why* a class-M file was edited.

The skill's job is orchestration: decide *which* class-M paths to push, confirm the fleet-wide blast radius, invoke the script once with all of them, and route every delivered project to its own session.

## Why this skill exists

The recurring true issue (surfaced dogfooding on `training-tracker` + `local-rag-client`, collected in PR #224): **delivery, not authorship, is the bottleneck.** Every correctness fix already exists in meta, but existing projects don't receive class-M updates unless someone manually runs a sync — so the fleet silently runs stale `.claude/` skill bodies and old CI templates. Concretely: a project held **2 of 14 skill bodies** while carrying 11 commands that delegate to absent skill files; another ran a **dead `shellcheck` gate** and `uv sync --frozen` months after meta fixed both. Broadcasting was possible before only one file at a time by hand. This skill makes "push the current class-M set to everyone" a single, repeatable, confirm-gated operation.

It is the **meta-side producer** paired with the project-side `alemax-complete-update` consumer: this STAGES the delivery; the project session decides + finishes. Meta broadcasts, the project decides — no PR, no meta-side merge.

## Behavior overview

0. **Step 0 — Context check.** Refuse unless in the claude-meta fork clone (`context: claude-meta-only`).
1. **Step 1 — Preflight.** `projects.yaml` populated (fork `aiml0NN`, not canonical), clean tree, `gh`/`yq`/`git` present.
2. **Step 2 — Resolve the artifact set.** Default = the **complete class-M set**, computed from `scaffolding/propagation-policy.yaml` at run time (50 paths today: 39 under `.claude/` + 11 templates). `--since <ref>` narrows to what changed since a ref. `--path <p>` (repeatable) adds explicit shipped paths. Map each to its `broadcast-update.sh --only` form.
3. **Step 3 — Present the plan + confirm.** Show the path list + the active-project count (the blast radius), and say whether the delivery is **complete** (pin advances) or **partial** (pin does not). Confirm explicitly. Offer `--dry-run`.
4. **Step 4 — Invoke.** One `broadcast-update.sh` call carrying all `--only` paths + a `--message`.
5. **Step 5 — Report + route.** Surface the per-project summary (delivered / no-op / skipped) and route **every delivered project** to `/alemax:complete-update` in its own session. There is no meta-side conflict outcome to route.

## Steps

### Step 0 — Context check

```bash
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
CURRENT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [[ "$ORIGIN_URL" != *"claude-meta"* || "$CURRENT_ROOT" != *"/claude-meta" ]]; then
  echo "ERROR: alemax-update-skills requires the claude-meta clone (context: claude-meta-only)." >&2
  exit 1
fi
if [[ "$ORIGIN_URL" == *"alemaxdesign/claude-meta"* ]]; then
  echo "ERROR: origin is canonical. Run from your FORK clone — broadcast reads projects.yaml, which is fork-divergent (populated on aiml0NN)." >&2
  exit 1
fi
META_ROOT="$CURRENT_ROOT"
```

### Step 1 — Preflight

```bash
[[ -z "$(git -C "$META_ROOT" status --porcelain)" ]] || { echo "tree dirty — commit/stash first"; exit 1; }
command -v gh >/dev/null && command -v yq >/dev/null && command -v git >/dev/null || { echo "need gh + yq + git"; exit 1; }
N_ACTIVE="$(yq -r '[.projects[] | select(.status == "active")] | length' "$META_ROOT/projects.yaml")"
if [[ "${N_ACTIVE:-0}" -eq 0 ]]; then
  echo "projects.yaml has no active projects — you are probably on canonical or a PR branch (empty manifest)." >&2
  echo "Broadcast reads the fork-divergent manifest; run from your aiml0NN clone." >&2
  exit 1
fi
```

### Step 2 — Resolve the artifact set

Build the `--only` path list. Each path is relative to a `broadcast-update.sh` scope root (`scaffolding/claude/skills` → `alemax-foo/SKILL.md`; `scaffolding/claude/commands` → `alemax/foo.md`; `scaffolding/claude/agents` → `foo.md`; `scaffolding/templates` → e.g. `.github/workflows/ci.yml`).

`PATHS` holds the scope-relative forms `--only` wants; `DESTS` holds the project-destination forms the completeness check compares against. Keep them in step.

```bash
PATHS=(); DESTS=()

# Default: the COMPLETE class-M set, computed from scaffolding/propagation-policy.yaml.
# NOT a glob over scaffolding/claude/ — that default omitted the 11 class-M template
# paths (ci.yml, .gitignore, .pre-commit-config.yaml, dependabot.yml, bin/**,
# ISSUE_TEMPLATE, PULL_REQUEST_TEMPLATE, .editorconfig, .gitattributes), which are
# already deliverable today because broadcast resolves --only against
# scaffolding/templates/ FIRST. Projects ran dead CI gates for months as a result.
# Completeness also decides whether the pin advances, so it must be COMPUTED.
if [[ -z "${SINCE:-}" ]]; then
  source "$META_ROOT/meta/bootstrap/lib/common.sh"
  source "$META_ROOT/meta/bootstrap/lib/propagation.sh"
  while IFS= read -r dest; do
    DESTS+=("$dest")
    case "$dest" in
      .claude/skills/*)   PATHS+=("${dest#.claude/skills/}") ;;
      .claude/commands/*) PATHS+=("${dest#.claude/commands/}") ;;
      .claude/agents/*)   PATHS+=("${dest#.claude/agents/}") ;;
      *)                  PATHS+=("$dest") ;;   # template → project root
    esac
  done < <(prop_complete_class_m_set "$META_ROOT")
else
  # --since <ref>: only class-M .claude artifacts changed since ref.
  while IFS= read -r f; do
    case "$f" in
      scaffolding/claude/skills/*)   PATHS+=("${f#scaffolding/claude/skills/}") ;;
      scaffolding/claude/commands/*) PATHS+=("${f#scaffolding/claude/commands/}") ;;
      scaffolding/claude/agents/*)   PATHS+=("${f#scaffolding/claude/agents/}") ;;
    esac
  done < <(git -C "$META_ROOT" diff --name-only "$SINCE" -- scaffolding/claude/)
fi

# --path <p> (repeatable): explicit shipped paths, e.g. the F5 ci.yml delivery.
for p in "${EXTRA_PATHS[@]:-}"; do [[ -n "$p" ]] && PATHS+=("$p"); done
```

`broadcast-update.sh` refuses class-P and placeholder-bearing paths itself, so a stray non-broadcastable path fails fast rather than shipping garbage. De-dup `PATHS` before use.

### Step 3 — Present the plan + confirm

Use the **AskUserQuestion tool**. Show: the resolved `--only` path count and list, the number of active projects the broadcast will touch, and **whether the delivery is complete**:

```bash
# Compare DESTINATION paths, not the scope-relative --only forms.
DELIVERED="$(mktemp)"; printf '%s\n' "${DESTS[@]}" > "$DELIVERED"
MISSING="$(prop_missing_from_complete_set "$META_ROOT" "$DELIVERED")"
[[ -z "$MISSING" ]] && echo "COMPLETE — each project's .meta-version WILL advance" \
                    || echo "PARTIAL — the pin will NOT advance; absent: $MISSING"
```

Say which it is. A complete delivery advances the pin, which keeps every future broadcast's merge base fresh; a partial one leaves the pin alone and the base keeps ageing. Default-recommended: run it, complete. Offer a dry-run first for a large set.

Explicit confirmation is **non-negotiable** — this stages a delivery on every active project.

### Step 4 — Invoke

```bash
ONLY_ARGS=(); for p in "${PATHS[@]}"; do ONLY_ARGS+=(--only "$p"); done
"$META_ROOT/meta/scripts/broadcast-update.sh" "${ONLY_ARGS[@]}" --message "$MSG" ${DRY_RUN:+--dry-run}
```

One invocation → all paths land in a single `meta-broadcast/<slug>` branch per project, plus a persistent `../<project>-claude-meta` worktree and a short `.local/HANDOFF.md`.

**`.meta-version`:** the script decides, not this skill. It advances the pin only when the delivered set covers the complete class-M set — computed from the policy manifest at run time. A partial delivery leaves it alone and names the absent paths. (`--stamp-pin` was removed and must not come back: it stamped unconditionally, which is the over-claim this rule exists to prevent.)

### Step 5 — Report + route

Surface the script's summary (**delivered / no-op / skipped**) and whether the pin advanced.

Route **every delivered project** to `/alemax:complete-update`, run **from that project's own session** — not just some of them, because meta no longer resolves anything and therefore produces no conflict outcome to triage. Do **not** offer `sync-from-meta.sh --name <p>` as a conflict remedy; there is no meta-side conflict.

Tell the operator two things explicitly:

- the staged worktrees are **left in place on purpose** — they carry the `complete-update` skill body to projects that don't have it yet — and should be removed only after each project reports completion;
- no-op projects were already current and got nothing;
- **`projects.yaml` is now stale for every delivered project, and this run cannot fix
  it.** `last_synced_sha` / `last_synced_at` are written only by `finalize-sync.sh`.
  This skill finishes *before* any project applies anything, so there is nothing
  truthful to record yet; and `/alemax:complete-update`, where the pin actually moves,
  runs in the project clone, which never touches meta's manifest. **Later**, once
  projects report completion, run `meta/scripts/reconcile-last-synced.sh` from the meta
  clone — it reads each project's on-disk `.meta-version`, so it is safe at any time and
  idempotent.

## When the delivery fixes `complete-update` itself — the bridge

If this broadcast changes `.claude/skills/alemax-complete-update/` **and** the target
project's installed copy is wrong *for this delivery*, the consumer cannot be trusted to
apply it: the buggy skill is what runs, and the fix is in the payload it is processing.
Check before delivering — `grep` the project's installed `SKILL.md` for the specific
defect, don't assume.

The handoff's normal route (copy the skill out of the worktree) **cannot** solve this:
that path is *in* the payload, so the copies are untracked at a path the cherry-pick
wants to write, and git aborts with *"untracked working tree files would be
overwritten"*. Phase 3a in `complete-update` handles the ordinary bootstrap case by
committing them first; it cannot help when the installed skill is the thing at fault.

**The bridge.** Hand-place the corrected skill body at a path that is **not** in the
payload — `.claude/skills/bridge-skills-update/` — so it can never collide, then point
the handoff at it instead of `/alemax:complete-update`.

1. Build it from meta's current `alemax-complete-update/SKILL.md`: strip the frontmatter,
   emit new frontmatter with `name: bridge-skills-update`, and prepend a header saying
   what it is, why the committed copy is wrong, and the two rules below.
2. Rewrite `.local/HANDOFF.md`: **do not run `/alemax:complete-update`**, run the bridge;
   name the branch and worktree as usual.
3. Both surfaces — bridge header *and* handoff — must independently carry:
   - **never commit it**: it shows in `git status` as untracked and `git add -A` will
     stage it, so stage explicit paths during the update;
   - **delete it when done**: `rm -rf .claude/skills/bridge-skills-update`.

**Do not hide it in `.git/info/exclude`.** Tried once: it makes `git add -A` safe but
removes the thing from `git status`, so a clean status reads as "nothing was staged" and
the delete reminder disappears with it. Visibility is the reminder.

Verified end-to-end on `training-tracker` (2026-08-15): the bridge carried the corrected
pin rule, the delivery applied, and afterwards the bridge was absent from disk with **0**
commits in the entire history mentioning it.

## Edge cases

- **Empty `projects.yaml`** — refused in Step 1 (you're on canonical or a PR branch; run from `aiml0NN`).
- **A path resolves to class P / has placeholders** — `broadcast-update.sh` refuses it; drop it from the set and re-run.
- **Fleet-scale run** — a delivery on every active project. Prefer `--dry-run` first. `--since <last-release-tag>` narrows it, but note the trade-off: a narrowed run is a PARTIAL delivery, so it will NOT advance any project's pin and every future broadcast keeps three-waying against the older base.
- **A project has uncommitted changes / no `.meta-version`** — the script skips it (reported in the summary); nothing to do here.
- **Delivering an UNMERGED skill for testing** — the script reads sources from the current checkout, but the fork manifest lives on `aiml0NN`. Use `MANIFEST=<single-project.yaml>` to target one project from the feature branch (how the completion skills were first dogfooded).

## system-path-rule

This skill operates under the meta clone (`scaffolding/`, `meta/scripts/`) and drives `broadcast-update.sh`, which works in throwaway worktrees under each project's `.git`. No macOS-system-rooted paths are touched.

## Cross-links

- `meta/scripts/broadcast-update.sh` — the multi-path push engine this wraps.
- `meta/bootstrap/lib/propagation.sh` — the SHARED base builder (`prop_build_orphan_pair`, `prop_base_include_path`, `prop_complete_class_m_set`) used by both flavours. Read its CLAUDE-SESSION NOTE before changing propagation behaviour.
- `.claude/skills/alemax-complete-update/SKILL.md` — project-side consumer that finishes a broadcast (cherry-pick, resolve conflicts locally, re-lock, apply deltas).
- `openspec/specs/vendored-artifact-sync/spec.md` — the push-path contract (one delivery per project carries all named paths; no PR; pin advances only on a complete class-M delivery).
- `openspec/changes/customer-driven-update-mature-projects/` — the spec for this flavour.
- `openspec/specs/scaffolding-propagation-tiers/spec.md` — the class-M / class-P model.

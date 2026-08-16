---
name: "ALEMAX: Complete Update"
description: Project-side completion of a meta update. Reads the meta side's .local/HANDOFF.md (or update-todo.md) to know what to check, finds the update branch it names (locally in a nearby git worktree, or remotely on origin), merges it into main, then re-locks, applies the migration/checks the handoff lists, runs tests, pushes, verifies CI. The customer never clones meta — the M/P content is in the branch. Consumer half of /alemax:update-skills.
category: Workflow
tags: [workflow, alemax, project-side, sync]
---

<!-- Governance preamble — see openspec-governance-canonical-only (archived 2026-05-29) -->

## Governance preamble (run BEFORE any other step)

This command runs from a **project clone** that received a meta update — not the meta-repo. It mutates only project-local state (the merge into `main`, lockfiles, conflict resolutions) — no canonical claude-meta surface is touched, and it **never clones or reaches into the meta-repo**: the class-M/P content is in the pushed branch, the briefing is in `.local/HANDOFF.md`.

Before doing anything else:

1. Run `git remote get-url origin` and `git rev-parse --show-toplevel`.
2. Apply the decision matrix:
   - **origin + root are the claude-meta meta-repo** → REFUSE with: "This is `context: project` — run it from the PROJECT clone. To PUSH an update from the meta-repo, use `/alemax:update-skills`."
   - **a project clone** → proceed. It reads `.local/HANDOFF.md` (or `update-todo.md`) for what to check and finds the update branch it names.

Once preflight passes, **delegate the rest to the `alemax-complete-update` skill** (`.claude/skills/alemax-complete-update/SKILL.md`).

---

## Context guard

This command requires a **project clone** (`context: project`). The skill body's Step 0 refuses on the meta-repo.

Skill declared context: `project` (per `.claude/skills/alemax-complete-update/SKILL.md` frontmatter, codified in `openspec/specs/alemax-skills/spec.md`).

---

## Input

The argument after `/alemax:complete-update` is optional:

- **No args** — default: read the handoff → find + merge the branch → complete per the handoff.
- **`--dry-run`** — enumerate; perform no mutations (no merge, no re-lock, no push).
- **`META_SRC=<path>`** (env) — a nearby worktree/clone holding the branch, for the offline / not-yet-pushed case.

Examples:

```
/alemax:complete-update
/alemax:complete-update --dry-run
META_SRC=/path/to/nearby/worktree /alemax:complete-update
```

## Behavior overview

1. **Phase 1 — Read the handoff** (`.local/HANDOFF.md` or `update-todo.md`): what this update is, the branch name, what to check. Drives the rest; the skill doesn't guess.
2. **Phase 2 — Find the branch** the handoff names — local ref / nearby worktree first, else fetch from origin. **No meta clone.**
3. **Phase 3 — Merge into `main`** (`--no-ff`; the branch is already reconciled meta-side — consume it). Guide conflicts.
4. **Phase 4 — Complete per the handoff** — re-lock (`uv lock`/`go mod tidy`), apply the migration deltas it names, the checks it lists.
5. **Phase 5 — Run project checks** (pre-commit + tests).
6. **Phase 6 — Push + verify CI + clean up** (delete the merged branch; clear the handoff).

Full procedure in `.claude/skills/alemax-complete-update/SKILL.md`.

## When NOT to use this skill

- **You want to PUSH an update to projects** (build + broadcast the branch) — that's `/alemax:update-skills`, meta-side.
- **No update branch and no handoff** — there's nothing to complete; the skill exits with "already current".
- **You're in the meta-repo** — the skill refuses.

## Cross-links

- `.claude/skills/alemax-complete-update/SKILL.md` — full skill body.
- `.claude/commands/alemax/update-skills.md` — meta-side producer: builds + pushes the branch and writes the handoff.
- `meta/scripts/broadcast-update.sh` — the worktree engine that reconciles + pushes the branch and writes `.local/HANDOFF.md`.
- `.claude/commands/alemax/complete-init.md` — sibling: finishes a *bootstrap* from the project side.
- `openspec/specs/project-side-completion/spec.md` — capability spec + handoff-note schema.

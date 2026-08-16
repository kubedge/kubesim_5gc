---
name: "ALEMAX: Front-burner (session resume)"
description: Operator-triggered "I'm picking up where I left off" skill. Reads `.local/resume.md` (produced by `/alemax:back-burner`) on a fresh Claude session, runs drift detection against the recorded snapshot, surfaces findings, and proposes a concrete next step. Strictly read-only on the working repo — never commits, stashes, or executes the proposed action. Pairs with `/alemax:back-burner` (producer).
category: Workflow
tags: [workflow, alemax, session-management]
---

<!-- Governance preamble — see openspec-governance-canonical-only (archived 2026-05-29) -->

## Governance preamble (run BEFORE any other step)

This command is **strictly read-only** on the operator's working repo. It reads `.local/resume.md` (gitignored per `dot-local-scratch-convention`), inspects git state, optionally fetches remote refs + lists PRs, and emits text. It does NOT commit, stash, write any file, mutate `.local/resume.md`, or invoke any other slash command. No branch / PR required for the read itself.

The skill MAY surface a phase-4 proposed next-action that *would* mutate canonical-only paths (`openspec/changes/`, `openspec/specs/`, `openspec/decisions.md`, `openspec/ideas.md`, `openspec/.openspec.yaml`) if executed on fork main. When that happens, the skill appends a governance reminder to the proposal — but never executes it. The operator decides what to do with the proposal in subsequent turns.

Before doing anything else:

1. Run `git remote get-url origin` and `git branch --show-current` to confirm the operator is in a git repo (the skill needs `git rev-parse --show-toplevel`).
2. The skill works from any branch in any claude-meta-managed repo — no branch restrictions.

Once preflight passes, **delegate the rest to the `alemax-front-burner` skill** (`.claude/skills/alemax-front-burner/SKILL.md`).

---

## Context guard

This command works from **any claude-meta-managed repo** — the meta-repo OR any project clone. The skill body's Step 0 detects which context (meta vs project) and reads from the current repo's `.local/resume.md`.

Skill declared context: `either` (per `.claude/skills/alemax-front-burner/SKILL.md` frontmatter, codified in `openspec/specs/alemax-skills/spec.md`).

---

## Input

The argument after `/alemax:front-burner` is optional:

- **No args** — default behavior: local-only four-phase resume.
- **`--check-remote`** — additionally `git fetch --no-write-fetch-head` and surface `origin/main` advancement since the recorded snapshot.
- **`--check-openspec`** — additionally enumerate new `openspec/changes/` directories + open canonical PRs via `gh pr list`.

Flags compose. Example:

```
/alemax:front-burner
/alemax:front-burner --check-remote
/alemax:front-burner --check-remote --check-openspec
```

## Behavior overview

1. **Phase 1 — Read checkpoint.** Open `.local/resume.md`; parse YAML frontmatter `schema_version`; route to v1-canonical / v2+-best-effort / malformed-degraded / standalone-mode (file absent → synthesize from `git merge-base HEAD origin/main`).
2. **Phase 2 — Drift detection.** Local-cheap signals always run (branch, HEAD, working-tree, stash). Remote-expensive signals run only on flag (origin/main advance via `--check-remote`; new openspec changes + open PRs via `--check-openspec`).
3. **Phase 3 — Surface findings.** Fixed scannable order: recorded next step → open questions → drift signals (branch → HEAD → working-tree → stash → remote → openspec). Staleness warning prepended (silent ≤24h / soft >24h–7d / strong >7d). One terminal line per finding; `[expand]` cue for multi-line.
4. **Phase 4 — Propose, never execute.** Three options: (a) resume recorded next step / (b) address top drift signal / (c) something else. Canonical-only governance reminder appended to (a) if the recorded next step would mutate `openspec/**` on fork main. Skill terminates after the operator selects.

Full procedure in `.claude/skills/alemax-front-burner/SKILL.md`.

## When NOT to use this skill

- **You want to actually run the recorded next step** — this skill proposes; you decide and run. Use `/alemax:apply` or the appropriate slash command in a follow-up turn.
- **You want to discard `.local/resume.md`** — delete it manually (`rm <repo-root>/.local/resume.md`) or run `/alemax:back-burner` to overwrite. This skill is read-only.
- **You want a multi-repo resume** — current repo only in v1.

## Cross-links

- `.claude/skills/alemax-front-burner/SKILL.md` — full skill body.
- `.claude/commands/alemax/back-burner.md` — paired producer skill (writes `.local/resume.md` at session end).
- `openspec/specs/alemax-skills/spec.md` — family conventions + `context: either` requirement.
- `openspec/specs/back-burner-session-wind-down/spec.md` — `.local/resume.md` schema (canonical source).
- `openspec/specs/front-burner-session-resume/spec.md` — this skill's behavioral spec (created at archive time).

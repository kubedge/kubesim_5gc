---
name: "ALEMAX: Back-burner (session wind-down)"
description: Operator-triggered end-of-session housekeeping. Walks the operator through five phases — checkpoint draft, /tmp cleanup, settings sanity-pass (both .claude/settings.json AND .claude/settings.local.json), working-tree audit, handoff prompt — producing a `.local/resume.md` checkpoint the paired `/alemax:front-burner` skill reads on the next session start. Read-only on both settings files. Never auto-invokes `/compact` or `/quit`.
category: Workflow
tags: [workflow, alemax, session-management]
---

<!-- Governance preamble — see openspec-governance-canonical-only (archived 2026-05-29) -->

## Governance preamble (run BEFORE any other step)

This command writes `.local/resume.md` at the current repo's root. The file is gitignored per `dot-local-scratch-convention` (archived 2026-06-01) so the mutation never gets committed. No branch / PR needed for the checkpoint itself.

The skill MAY commit other files during phase 4 (working-tree audit) if the operator selects "commit now" for an unstaged change. Those commits respect the canonical-only rule: if the staged path is under `openspec/changes/`, `openspec/specs/`, `openspec/decisions.md`, `openspec/ideas.md`, or `openspec/.openspec.yaml` AND the current branch is fork main, the skill refuses option (a) and re-offers options (b) stash, (c) record-as-open, (d) ignore.

Before doing anything else:

1. Run `git remote get-url origin` and `git branch --show-current` to confirm the operator is in a git repo (the skill needs `git rev-parse --show-toplevel`).
2. The skill works from any branch in any claude-meta-managed repo — no branch restrictions for the checkpoint write itself.

Once preflight passes, **delegate the rest to the `alemax-back-burner` skill** (`.claude/skills/alemax-back-burner/SKILL.md`).

---

## Context guard

This command works from **any claude-meta-managed repo** — the meta-repo OR any project clone. The skill body's Step 0 detects which context (meta vs project) and writes to the current repo's `.local/resume.md`.

Skill declared context: `either` (per `.claude/skills/alemax-back-burner/SKILL.md` frontmatter, codified in `openspec/specs/alemax-skills/spec.md`).

---

## Input

The argument after `/alemax:back-burner` is optional:

- **No args** — default behavior: conversational five-phase walkthrough.
- **`--dry-run`** — each phase ENUMERATES what it would do but PERFORMS none. No file writes, no `rm`, no `git commit`, no `git stash`.

Examples:

```
/alemax:back-burner
/alemax:back-burner --dry-run
```

## Behavior overview

1. **Phase 1 — Checkpoint draft.** `.gitignore` precondition → operator prompts for "Next step" prose → write `.local/resume.md` with versioned YAML frontmatter + canonical body sections.
2. **Phase 2 — /tmp cleanup.** Enumerate `/tmp/claude-*` files newer than the session floor; per-candidate confirm; never touch files outside the `/tmp/claude-*` prefix.
3. **Phase 3 — Settings sanity-pass.** Read BOTH `.claude/settings.json` AND `.claude/settings.local.json` (the operator-local file accumulates Claude Code's session-grant `permissions.allow` adds). Emit per-file header; report candidate session-scoped overrides using three sharpened heuristics (absolute `/Volumes/AIML0NN/...` paths / long literal arg strings >100 chars / literal full commands with no glob metacharacters); ask whether to note for revert. **READ-ONLY** — never writes to either file.
4. **Phase 4 — Working-tree audit (advisory).** Surface unstaged / staged / untracked / new-stashes. Per-item options: (a) commit, (b) stash, (c) record-as-open in resume.md, (d) ignore. Canonical-only guard refuses (a) for `openspec/**` on fork main.
5. **Phase 5 — Handoff prompt.** Print exact text: `Wind-down complete. Run /compact, then /quit when ready.` and exit. Never auto-invokes either command.

Full procedure in `.claude/skills/alemax-back-burner/SKILL.md`.

## When NOT to use this skill

- **You want to commit work** — use `git` directly. This skill includes a commit option in phase 4 for convenience, but it's not a commit interface.
- **You want to switch projects mid-session** — wind-down assumes session-end. Use `/alemax:front-burner` from the next project's clone instead.
- **You want to `/compact` and `/quit`** — the skill prompts you to run those at the end; it does not run them itself.

## Cross-links

- `.claude/skills/alemax-back-burner/SKILL.md` — full skill body.
- `.claude/commands/alemax/front-burner.md` — paired consumer skill (reads `.local/resume.md` on next session start).
- `openspec/specs/alemax-skills/spec.md` — family conventions + `context: either` requirement.
- `openspec/specs/spec-governance/spec.md` — `.local/` convention from `dot-local-scratch-convention`.
- `openspec/specs/back-burner-session-wind-down/spec.md` — `.local/resume.md` schema canonical source.

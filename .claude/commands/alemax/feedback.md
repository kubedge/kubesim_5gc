---
name: "ALEMAX: Feedback"
description: Lightweight per-repo feedback capture. Prompts conversationally for context + finding + severity, appends a structured row to `.local/feedback.md` at the current repo's root. Works from any claude-meta-managed repo (meta or project).
category: Workflow
tags: [workflow, alemax, capture]
---

<!-- Governance preamble — see openspec-governance-canonical-only (archived 2026-05-29) -->

## Governance preamble (run BEFORE any other step)

This command writes to `.local/feedback.md` at the current repo's root. The file is gitignored per `dot-local-scratch-convention` (archived 2026-06-01) so the mutation never gets committed. No branch / PR needed.

Before doing anything else:

1. Run `git remote get-url origin` and `git branch --show-current` to confirm the operator is in a git repo (the skill needs `git rev-parse --show-toplevel`).
2. The skill works from any branch in any claude-meta-managed repo — no branch restrictions.

Once preflight passes, **delegate the rest to the `alemax-feedback` skill** (`.claude/skills/alemax-feedback/SKILL.md`).

---

## Context guard

This command works from **any claude-meta-managed repo** — the meta-repo OR any project clone. The skill body's Step 0 detects which context (meta vs project) and writes to the current repo's `.local/feedback.md`.

Skill declared context: `either` (per `.claude/skills/alemax-feedback/SKILL.md` frontmatter, codified in `openspec/specs/alemax-skills/spec.md`).

---

## Input

The argument after `/alemax:feedback` is optional:

- **No args** — default behavior: conversational prompts for context + finding + severity + (optional) related diagnosis.
- **`--related-diagnosis <path>`** — pre-populate the related-diagnosis field with the supplied path.

Examples:

```
/alemax:feedback
/alemax:feedback --related-diagnosis .local/diagnosis/docker-auth-loop/
```

## Steps

1. **Preflight** — verify git repo + clean / dirty doesn't matter.
2. **Step 0 (Context check)** — detect meta vs project; `either` means no refusal.
3. **Prompt for Context** — what the operator was doing.
4. **Prompt for Finding** — friction / bug / idea / observation.
5. **Prompt for Severity** — one of `blocker` / `friction` / `idea` / `harness`.
6. **Optional Related diagnosis link**.
7. **Build + append the row** to `.local/feedback.md` (create file if missing).
8. **Confirm** to operator with summary.

Full procedure in `.claude/skills/alemax-feedback/SKILL.md`.

## When NOT to use this skill

- **The finding warrants a full diagnosis doc** — use `/alemax:diagnose` instead. Feedback rows are 1-3 sentences each; diagnoses are multi-section investigations.
- **The finding should go DIRECTLY into the canonical backlog** — open a PR to `openspec/ideas.md` yourself. The `/alemax:collect-feedback` skill (future; see `alemax-collect-feedback-skill` idea) will batch-promote feedback into the backlog when it ships.
- **You want to track in-progress work** — that's what `tasks.md` checkboxes are for; this skill is for findings that don't yet have a change scoped.

## Cross-links

- `.claude/skills/alemax-feedback/SKILL.md` — full skill body.
- `openspec/specs/alemax-skills/spec.md` — family conventions + `context: either` requirement.
- `openspec/specs/spec-governance/spec.md` — `.local/` convention.
- `/alemax:diagnose` — sibling skill for full diagnosis docs.
- Future `alemax-collect-feedback-skill` — the collector that will parse these rows.

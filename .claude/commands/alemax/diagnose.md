---
name: "ALEMAX: Diagnose"
description: Scaffold a new diagnosis directory with the standardized 10-section template. Conversationally prompts for topic + scope + symptom + starting hypothesis; smart-defaults location based on current context. Matches the shape of existing diagnoses in `openspec/diagnosis/`.
category: Workflow
tags: [workflow, alemax, diagnosis]
---

<!-- Governance preamble — see openspec-governance-canonical-only (archived 2026-05-29) -->

## Governance preamble (run BEFORE any other step)

This command scaffolds a directory at either `openspec/diagnosis/<date>-<topic>/` (committed; for cross-project diagnoses) or `.local/diagnosis/<topic>/` (operator-local; for project-specific or pre-promotion diagnoses). The first path lands in canonical via a PR; the second lives in operator-local scratch (gitignored per `dot-local-scratch-convention`).

Before doing anything else:

1. Run `git remote get-url origin` and `git branch --show-current` to confirm the operator is in a git repo.
2. If the operator chooses `openspec/diagnosis/` as the location, the resulting commit + PR goes to canonical claude-meta per the canonical-only governance rule. The skill handles the branching internally.
3. If the operator chooses `.local/diagnosis/`, no branch / PR — the directory is gitignored.

Once preflight passes, **delegate the rest to the `alemax-diagnose` skill** (`.claude/skills/alemax-diagnose/SKILL.md`).

---

## Context guard

This command works from **any claude-meta-managed repo** — the meta-repo OR any project clone. The skill body's Step 0 detects which context (meta vs project) and smart-defaults the diagnosis location based on it (meta-repo → `openspec/diagnosis/`; project → `.local/diagnosis/`). Operator may override.

Skill declared context: `either` (per `.claude/skills/alemax-diagnose/SKILL.md` frontmatter, codified in `openspec/specs/alemax-skills/spec.md`).

---

## Input

The argument after `/alemax:diagnose` is optional:

- **No args** — default behavior: conversational prompts for location + topic + scope + symptom + starting hypothesis.
- **`<topic-slug>`** — pre-populate the topic slug (skip the topic prompt; still asks for the other fields).
- **`--local`** — force `.local/diagnosis/` regardless of context (skip the location prompt).
- **`--committed`** — force `openspec/diagnosis/` regardless of context.

Examples:

```
/alemax:diagnose
/alemax:diagnose docker-auth-loop
/alemax:diagnose --local
```

## Steps

1. **Preflight** — verify git repo.
2. **Step 0 (Context check)** — detect meta vs project; smart-default location.
3. **Location prompt** — present default + alternative; operator confirms or overrides.
4. **Topic slug prompt** — kebab-case lowercase; validate + re-prompt on invalid.
5. **Scope, symptom, starting hypothesis prompts** — each free-form.
6. **Build the directory path** with collision handling.
7. **Write `diagnosis.md`** populated with the standardized template + operator-supplied values.
8. **Confirm** with path; mention conversational fill-in.

Full procedure in `.claude/skills/alemax-diagnose/SKILL.md`.

## When NOT to use this skill

- **A 1-3 sentence finding** — use `/alemax:feedback` instead. Diagnoses are for multi-section investigations.
- **You want to scope a change directly** — use `/opsx:propose` instead. Diagnoses document FINDINGS; OpenSpec changes propose SOLUTIONS.
- **The investigation is already complete and you want to write a change** — go directly to `/opsx:propose`. Diagnoses are for in-progress investigation work.

## Cross-links

- `.claude/skills/alemax-diagnose/SKILL.md` — full skill body.
- `openspec/diagnosis/README.md` — the diagnosis-dir convention this skill extends.
- `openspec/specs/alemax-skills/spec.md` — family conventions + `context: either` requirement.
- `/alemax:feedback` — sibling skill for one-line findings.
- `/opsx:propose` — when the diagnosis crystallizes into a proposal.

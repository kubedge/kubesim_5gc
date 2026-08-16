---
name: "ALEMAX: Collect feedback"
description: Drain `.local/feedback.md` from every project in projects.yaml, three-stage-classify each finding (dedup + harness + operator confirmation), emit a single canonical PR matching PR #80's shape. Closes the alemax-feedback cluster (`/alemax:feedback` + `/alemax:diagnose` + this skill).
category: Workflow
tags: [workflow, alemax, collect, harvest]
---

<!-- Governance preamble — see openspec-governance-canonical-only (archived 2026-05-29) -->

## Governance preamble (run BEFORE any other step)

This command mutates `openspec/ideas.md` in canonical claude-meta (via PR) and annotates each project's `.local/feedback.md` post-collection. The PR routing follows the canonical-only governance rule.

Before doing anything else:

1. Run `git remote get-url origin` and `git branch --show-current` in the meta-repo clone.
2. Apply the decision matrix:
   - **origin contains `alemaxdesign/claude-meta` AND branch = `main`** → proceed with soft warning; skill creates a feature branch internally.
   - **origin is a fork AND branch = `main`** → proceed; skill branches off `main` internally.
   - **origin is a fork AND branch ≠ `main`** → proceed; skill branches off `main` internally (PR targets canonical).
3. Verify the working tree is clean.

Once preflight passes, **delegate the rest to the `alemax-collect-feedback` skill** (`.claude/skills/alemax-collect-feedback/SKILL.md`).

---

## Context guard

This command requires the operator to be in their **claude-meta clone** (meta-repo), not a downstream project. The skill body's Step 0 verifies this and refuses on mismatch. If you're seeing this skill listed from a project clone session (post-`ship-alemax-skills-in-projects`), `cd` to your meta-repo clone first.

Skill declared context: `claude-meta-only` (per `.claude/skills/alemax-collect-feedback/SKILL.md` frontmatter, codified in `openspec/specs/alemax-skills/spec.md`).

---

## Input

The argument after `/alemax:collect-feedback` is optional:

- **No args** — default behavior: per-row classification prompts at every stage.
- **`--yes-all`** — bulk-accept default classifications for stages 1 and 2 (dedup, harness). Stage 3 (aggregated confirmation) still presents the final table for a single accept. Use when you've already eyeballed the per-project files manually.
- **`--project <name>`** — collect only from the named project (skip others). Useful for testing or when you want to drain ONE project before promoting findings to canonical.

Examples:

```
/alemax:collect-feedback
/alemax:collect-feedback --yes-all
/alemax:collect-feedback --project american-dream
```

## Steps

1. **Preflight** — clean tree, `projects.yaml` present, `yq` available.
2. **Step 0 (Context check)** — refuse with cd-to-meta hint if invoked from a project clone.
3. **Walk projects.yaml** — extract `(name, local_path)` for active projects.
4. **Per-project parse** — read `.local/feedback.md` if present; skip already-collected rows (post-annotation marker).
5. **Stage 1 — Dedup** — text-match each row against archived + active changes; surface candidates per row.
6. **Stage 2 — Harness classification** — keyword heuristic; prompt on ambiguous.
7. **Stage 3 — Operator confirmation** — aggregated table; per-row overrides allowed.
8. **PR emission** — branch + append `[ ]` entries to `openspec/ideas.md` + commit + push + open PR matching PR #80's shape.
9. **Post-collection annotation** — append `(collected YYYY-MM-DD → PR #<num>)` to consumed source rows.

Full procedure in `.claude/skills/alemax-collect-feedback/SKILL.md`.

## When NOT to use this skill

- **You only have feedback in ONE project that you want to discuss conversationally** — open a `/opsx:propose` directly instead. The collector is for batching.
- **The findings haven't been captured via `/alemax:feedback` first** — this skill consumes rows in the standard format. Manually-edited `.local/feedback.md` files may not parse cleanly.
- **You're inside a project clone** — the skill refuses; `cd` to the meta-repo clone first.

## Cross-links

- `.claude/skills/alemax-collect-feedback/SKILL.md` — full skill body.
- `/alemax:feedback` — sibling that produces the rows this consumes.
- `/alemax:diagnose` — sibling for deeper investigations.
- `openspec/specs/alemax-skills/spec.md` — family conventions + this skill's requirement.
- `openspec/specs/spec-governance/spec.md` — `.local/` convention; canonical-only governance.

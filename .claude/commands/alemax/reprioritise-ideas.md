---
name: "ALEMAX: Reprioritise ideas"
description: Curate § Suggested next-up of openspec/ideas.md — walk § Raw ideas, present `[ ]` entries with one-line summaries, let the operator pick 3–5 to surface as "next up", write pointer-only entries. Operator-triggered, often before planning sessions. Does NOT touch § Archived ideas or § Raw ideas content.
category: Workflow
tags: [workflow, openspec, alemax, planning]
---

<!-- Governance preamble — see openspec-governance-canonical-only (archived 2026-05-29) -->

## Governance preamble (run BEFORE any other step)

This command mutates `openspec/ideas.md`. It is **context-adaptive** and the skill handles the branching internally:
- **In the claude-meta meta-repo**, `openspec/ideas.md` is canonical-only — the mutation lands via a feature branch + PR to canonical, never as a direct commit to fork main.
- **In any other repo** (a bootstrapped project), `openspec/ideas.md` is owned by that repo — the mutation is committed on a branch against the repo's own `origin`; no `upstream` and no canonical-only rule apply.

Before doing anything else:

1. Run `git remote get-url origin` and `git branch --show-current`.
2. Apply the decision matrix:
   - **origin contains `alemaxdesign/claude-meta`** (the meta-repo) → proceed; the skill will branch off `main` internally and open a PR to canonical regardless of the current branch.
   - **origin is any other repo** → proceed; the skill operates on that repo's own `openspec/ideas.md` and commits on a branch against its own `origin`.
3. Verify the working tree is clean. The skill refuses to proceed on a dirty tree.

Once preflight passes, **delegate the rest to the `alemax-reprioritise-ideas` skill** (`.claude/skills/alemax-reprioritise-ideas/SKILL.md`).

---

## Context guard

This command is **context-adaptive** (`context: either`): it runs both in the claude-meta meta-repo and in any bootstrapped project. The skill body's Step 1 Preflight refuses only when the current repo has no `openspec/ideas.md` at its root (nothing to curate) — not on the meta-vs-project distinction.

Skill declared context: `either` (per `.claude/skills/alemax-reprioritise-ideas/SKILL.md` frontmatter, codified in `openspec/specs/alemax-skills/spec.md`).

---

## Input

The argument after `/alemax:reprioritise-ideas` is optional:

- **No args** — default behavior: present § Raw ideas list, conversational pick.
- **`--clear`** — clear § Suggested next-up (no new entries, replace with empty). Useful after a planning session whose picks have all shipped.

Examples:

```
/alemax:reprioritise-ideas
/alemax:reprioritise-ideas --clear
```

## Steps

1. **Preflight** — detect context, verify `openspec/ideas.md` present, clean working tree.
2. **Walk § Raw ideas** — extract every `[ ]` entry's slug + one-line summary.
3. **Present + pick** — show the numbered list; operator picks 3–5 by index or slug.
4. **Detect existing § Suggested next-up** — if non-empty, ask Replace / Add to / Skip.
5. **Atomic write** the mutated `openspec/ideas.md`.
6. **Branch + commit + push** — in claude-meta, open a PR to canonical; in a project, push to the repo's own origin.
7. **Summary**.

Full procedure in `.claude/skills/alemax-reprioritise-ideas/SKILL.md`.

## When NOT to use this skill

- **§ Raw ideas has zero `[ ]` entries** — nothing to surface; skill exits cleanly.
- **You want to ADD just one entry to § Suggested next-up** — that's fine; the skill supports the "add" mode when existing entries are present. But hand-editing the file is also OK for a single-entry add.
- **§ Suggested next-up is meant to mirror § Raw ideas** — it's not. § Suggested next-up is for a curated 3–5; if you want the full list, just scroll to § Raw ideas.

## Cross-links

- `.claude/skills/alemax-reprioritise-ideas/SKILL.md` — full skill body.
- `openspec/specs/spec-governance/spec.md` — the rhythm-based ideas.md structure this skill operates on.
- `openspec/specs/alemax-skills/spec.md` — family conventions.
- `/alemax:archive-ideas` — sibling skill for § Archived ideas — by capability reshape.

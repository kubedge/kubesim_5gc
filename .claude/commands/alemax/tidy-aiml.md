---
name: "ALEMAX: Tidy aiml0NN"
description: Reshape the current aiml0NN per-drive branch into the canonical operator-state shape (origin/main + 4 yaml commits + non-yaml on top). Conversational wrapper around meta/scripts/fork-tidy-aiml.sh.
category: Workflow
tags: [workflow, fork-sync, history, alemax]
---

<!-- Governance preamble — this skill rewrites fork-divergent state; no canonical-only mutation -->

## Governance preamble (run BEFORE any other step)

This command rewrites **fork-divergent** history — the aiml0NN per-drive branch on the operator's own fork. No canonical surface is touched. The canonical-only rule ([[openspec-governance-canonical-only]]) does not bite here — there is no canonical PR to open.

The command IS destructive: it requires a force-push-with-lease at the end. The branch lives on the operator's fork and has no downstream consumers (per the fork-divergent model — only the operator's own clones read aiml0NN), so force-with-lease is the safe primitive. The skill still requires explicit operator confirmation before the rewrite.

Before doing anything else:

1. Run `git remote get-url origin` and `git branch --show-current`.
2. Apply the decision matrix:
   - **origin contains `alemaxdesign/claude-meta`** → REFUSE. Canonical has no aiml0NN branches; this skill has nothing to do there.
   - **origin is a fork AND branch matches `^aiml[0-9]{2}$`** → proceed. Expected case.
   - **origin is a fork AND branch = `main`** → REFUSE with: "Switch to your aiml0NN branch first — `git checkout aiml0NN`. This skill rewrites aiml0NN history."
   - **any other branch (feature branch, detached HEAD)** → REFUSE with the same hint. The skill body's Step 0 enforces this anyway.
3. Verify working tree is clean (`git status --porcelain` is empty). If not, refuse and ask the operator to stash, commit, or discard pending changes first.

Once the preflight passes, **delegate the rest of the flow to the `alemax-tidy-aiml` skill** (`.claude/skills/alemax-tidy-aiml/SKILL.md`). The skill owns the dry-run preview, conversational classification of any mixed-file commits, confirmation, and final invocation with the appropriate flags.

---

## Context guard

This command requires the operator to be in their **claude-meta clone** (meta-repo), not a downstream project. The skill body's Step 0 verifies this and refuses on mismatch.

Skill declared context: `claude-meta-only` (per `.claude/skills/alemax-tidy-aiml/SKILL.md` frontmatter).

---

## Input

The argument after `/alemax:tidy-aiml` is one of:

- **Nothing** (operator just typed `/alemax:tidy-aiml`) — delegate to the skill's full flow (preview, confirm, apply, optional push).
- **`--push`** — operator wants the result published in one shot; the skill still confirms before doing it, then invokes `fork-tidy-aiml.sh --yes --push`.
- **`--dry-run`** — read-only mode; just surface the proposed shape vs current shape and stop. The skill invokes `fork-tidy-aiml.sh --dry-run` and reports.

## Behavior

Read the operator's input. If `--push` or `--dry-run` is present, thread it through to the skill's invocation. Otherwise hand off to the skill with defaults.

The skill's 5 steps (per `.claude/skills/alemax-tidy-aiml/SKILL.md`):

1. Step 0 — Context check (claude-meta, fork, aiml0NN branch).
2. Step 1 — Preflight (clean tree, origin/main not ahead of the branch, fork main not behind canonical `upstream/main`).
3. Step 2 — Dry-run preview to classify commits + surface mixed-file commits.
4. Step 3 — Present plan + confirm (explicitly — force-push is involved).
5. Step 4 + 5 — Invoke `meta/scripts/fork-tidy-aiml.sh` and report new shape.

**Step 3 (explicit confirmation) is non-negotiable**, even with `--push` shorthand. Positional input expresses intent, not consent to history rewriting + force-push.

## Output

After the skill's step 5, the slash command itself adds nothing; the skill's final report (new `git log origin/main..aiml0NN`) is the output. If the operator did NOT pass `--push`, the report ends with the manual push command (`git push --force-with-lease origin <branch>`).

---
name: "ALEMAX: Update Skills"
description: Meta-side fleet broadcast of the COMPLETE class-M artifact set (skills, commands, agents, and the class-M templates like ci.yml), computed from propagation-policy.yaml. Wraps the multi-path broadcast-update.sh — stages one unresolved [base <- update] branch per active project plus a persistent worktree and a short handoff, and opens NO PR. Meta does not merge; every delivered project finishes from its own session via /alemax:complete-update. Fixes the "delivery, not authorship" gap.
category: Workflow
tags: [workflow, alemax, meta, broadcast, propagation]
---

<!-- Governance preamble — see openspec-governance-canonical-only (archived 2026-05-29) -->

## Governance preamble (run BEFORE any other step)

This command opens PRs across the whole active-project fleet. It does NOT commit to any project's `main` and does NOT mutate any canonical claude-meta surface — each project gets a reviewable `meta-broadcast/*` PR, 3-way merged against that project's pinned meta version. The meta side broadcasts; the project's own session decides whether to merge (never resolve a project's conflicts from here).

Before doing anything else:

1. Run `git remote get-url origin` and `git branch --show-current`.
2. Apply the decision matrix:
   - **origin is canonical (`alemaxdesign/claude-meta`)** → REFUSE: "Run from your FORK clone — broadcast reads `projects.yaml`, which is fork-divergent (populated on `aiml0NN`); canonical's is empty."
   - **origin is a fork AND `projects.yaml` has ≥1 active project** → proceed.
   - **`projects.yaml` empty** (you're on a PR branch or canonical) → REFUSE with the aiml0NN hint.
3. Verify the working tree is clean.

Once preflight passes, **delegate the rest to the `alemax-update-skills` skill** (`.claude/skills/alemax-update-skills/SKILL.md`).

---

## Context guard

Requires the operator's **fork clone** on its `aiml0NN` branch (`context: claude-meta-only`, plus a populated fork manifest). The skill body's Step 0 + Step 1 enforce this.

Skill declared context: `claude-meta-only` (per `.claude/skills/alemax-update-skills/SKILL.md` frontmatter).

---

## Input

- **No args** — broadcast the full current class-M `.claude/` artifact set (skills + commands + agents) to every active project.
- **`--since <ref>`** — only class-M `.claude/` artifacts changed since `<ref>` (e.g. the last release tag). Preferred for routine runs.
- **`--path <p>`** (repeatable) — add explicit shipped paths, e.g. `--path .github/workflows/ci.yml` to deliver the shellcheck/`--locked` CI fixes (F5).
- **`--dry-run`** — enumerate the paths + target projects; open no PRs.

Examples:

```
/alemax:update-skills --dry-run
/alemax:update-skills --since v0.1.3
/alemax:update-skills --path .github/workflows/ci.yml --message "deliver CI correctness fixes"
```

## Behavior overview

1. **Step 0/1 — Context + preflight** (fork clone, populated manifest, clean tree).
2. **Step 2 — Resolve the `--only` set** (full `.claude/` class-M set, or `--since` delta, plus `--path` extras).
3. **Step 3 — Present the plan + confirm** (path list + active-project count = blast radius). Non-negotiable confirm; offer `--dry-run`.
4. **Step 4 — Invoke `broadcast-update.sh`** once with all paths → one staged delivery per project (branch + persistent `../<project>-claude-meta` worktree + `.local/HANDOFF.md`). No PR is opened.
5. **Step 5 — Report + route** conflicted projects to `/alemax:complete-update` / `sync-from-meta.sh`.

Full procedure in `.claude/skills/alemax-update-skills/SKILL.md`.

## When NOT to use this skill

- **You want to pull meta changes INTO a project** — that's `sync-from-meta.sh` / `finalize-sync.sh` (or `/alemax:complete-update` on the project side).
- **You want to change one file in one project** — use `broadcast-update.sh --only <path>` directly, or edit in that clone.
- **You're on canonical or a PR branch** — the manifest is empty; the skill refuses.

## Cross-links

- `.claude/skills/alemax-update-skills/SKILL.md` — full skill body.
- `.claude/commands/alemax/complete-update.md` — project-side consumer that finishes a broadcast.
- `meta/scripts/broadcast-update.sh` — the multi-path engine this wraps.
- `openspec/specs/vendored-artifact-sync/spec.md` — the push-path contract.

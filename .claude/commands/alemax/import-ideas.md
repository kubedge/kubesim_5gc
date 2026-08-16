---
name: "ALEMAX: Import ideas"
description: Drain an Obsidian vault of mobile-captured ideas — walk for `ideas-on-the-go(-<projectname>)?.md` files, route each file by its filename (cross-cutting / existing-project / new-project-chain), and per row ask only yes/skip-personal. Default vault is Obsidian's iCloud container at `iCloud~md~obsidian/Documents/AlemaxIdeas/`.
category: Workflow
tags: [workflow, capture, alemax, obsidian]
---

<!-- Governance preamble — see openspec-governance-canonical-only (archived 2026-05-29) -->

## Governance preamble (run BEFORE any other step)

This command mutates `openspec/ideas.md` in canonical claude-meta (for cross-cutting routes) and in target project repos (for existing-project routes). Every mutation lands via a feature branch + PR — never a direct commit to fork main. The skill handles the branching internally.

Before doing anything else:

1. Run `git remote get-url origin` and `git branch --show-current` in the operator's meta-repo clone.
2. Apply the decision matrix:
   - **origin contains `alemaxdesign/claude-meta` AND branch = `main`** → proceed; skill will branch internally for any meta-repo mutations.
   - **origin is a fork AND branch = `main`** → proceed; skill will branch off `main` internally for any meta-repo mutations.
   - **origin is a fork AND branch ≠ `main`** → proceed; skill will branch off `main` internally.
3. Verify working trees are clean in the meta-repo clone AND any project clone the skill might touch (skill will warn per-project at the existing-project routing step).

Once preflight passes, **delegate the rest to the `alemax-import-ideas` skill** (`.claude/skills/alemax-import-ideas/SKILL.md`).

---

## Context guard

This command requires the operator to be in their **claude-meta clone** (meta-repo), not a downstream project. The skill body's Step 0 verifies this and refuses on mismatch. If you're seeing this skill listed from a project clone session (post-`ship-alemax-skills-in-projects`), `cd` to your meta-repo clone first.

**Exception**: `--only <project>` lets the operator run this from a project clone when the vault contains only that project's `ideas-on-the-go-<project>.md`. Cross-cutting and other-project routes are skipped; stage-1 dedup still runs against the sibling meta-repo clone (or `$META_REPO_PATH`).

Skill declared context: `claude-meta-only` (per `.claude/skills/alemax-import-ideas/SKILL.md` frontmatter, codified in `openspec/specs/alemax-skills/spec.md`).

---

## Input

The argument after `/alemax:import-ideas` is one of:

- **Nothing** — drain all pending entries.
- **`--dry-run`** — list each pending entry + Claude's tentative classification; no mutations, no PRs.
- **`--only <project>`** — drain only `ideas-on-the-go-<project>.md`; allowed from a project clone (relaxes the `claude-meta-only` guard). Use when the vault contains only the current project's file and re-routing back to that project is the only action needed.

## Behavior

1. **Resolve the vault.** Read `users.yaml.ideas_on_the_go_vault` (preferred field), fall back to legacy `ideas_on_the_go_path` (deprecated alias with runtime warn), fall back to the literal default `/Users/<u>/Library/Mobile Documents/iCloud~md~obsidian/Documents/AlemaxIdeas/` — Obsidian's iCloud container per `obsidian-as-canonical-markdown-surface` (`openspec/specs/alemax-skills/spec.md`). Paths use literal `/Users/<u>/...` per the `system-path-rule` (same spec). Refuse if the vault folder doesn't exist.
2. **Walk the vault** for files matching `^ideas-on-the-go(-(.+))?\.md$`, sorted by mtime (oldest first). The `<projectname>` capture group is the routing key — empty for the un-suffixed `ideas-on-the-go.md`.
3. **iCloud-freshness check** per file (advisory).
4. **Per-file routing** by `<projectname>`:
   - empty (un-suffixed) OR `claude-meta` → cross-cutting (canonical claude-meta's `openspec/ideas.md`)
   - matches `projects.yaml.name` → existing-project (that project's `openspec/ideas.md`)
   - unknown → prompt operator "Create new project `<name>`?"; on yes chain through `/alemax:new-project`; on no ask "(a) cross-cutting / (b) skip / (c) cancel"
5. **Per-row yes/skip-personal** — within each routed file, ask exactly one question per pending `- [ ]` row. No per-row routing classification (the filename has already routed).
6. **Atomic file rewrite** with the route summary + source filename embedded.
7. **Final summary** broken down per file + aggregate totals.

The 7 steps are documented in `.claude/skills/alemax-import-ideas/SKILL.md`. The slash command's job is the governance preamble + the input parsing.

## Output

After the skill's step 6 summary, the slash command itself adds nothing. The operator's next manual actions are:

- **Review and merge** the per-route PRs (one per routed entry).
- **Re-run `/alemax:import-ideas`** later — already-annotated entries are skipped automatically.

## See also

- `.claude/skills/alemax-import-ideas/SKILL.md` — the skill body
- `meta/docs/ALEMAX-SKILLS.md` — the `/alemax:*` family convention
- `[[openspec-governance-canonical-only]]` — why every route opens a PR
- `[[mobile-capture-workflow]]` — the design + decisions behind this workflow

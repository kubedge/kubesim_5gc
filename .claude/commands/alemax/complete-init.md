---
name: "ALEMAX: Complete Init"
description: Project-side completion of a freshly-bootstrapped project (freshness-gated; refuses a long-running project unless --force). Keychain secrets, origin/HEAD, fresh-bootstrap hygiene (.python-version, seed .claude/settings.local.json before the first merge — never a tracked settings.json, ci.yml stack-trim), go-stack post-generate, verify (+ propose /doctor /test /security), guide the first real change → push → merge, then drop the bootstrap nudge. Consumer half of /alemax:new-project.
category: Workflow
tags: [workflow, alemax, project-side, bootstrap]
---

<!-- Governance preamble — see openspec-governance-canonical-only (archived 2026-05-29) -->

## Governance preamble (run BEFORE any other step)

This command runs from a **bootstrapped project clone**, not the meta-repo. It mutates only project-local state (Keychain, the project's `origin/HEAD`, the project's `CLAUDE.md` nudge) — no canonical claude-meta surface is touched, so the canonical-only rule does not apply here.

Before doing anything else:

1. Run `git remote get-url origin` and `git rev-parse --show-toplevel`.
2. Apply the decision matrix:
   - **origin + root are the claude-meta meta-repo** → REFUSE with: "This is `context: project` — run it from a bootstrapped PROJECT clone. To create a project, use `/alemax:new-project` from the meta-repo."
   - **no `.meta-version` at the root** → REFUSE with: "Not a claude-meta-bootstrapped project. Retrofitting an existing repo is a meta-side operation (`retrofit-project.sh`)."
   - **an established / long-running clone** (commit count past a fresh bootstrap) → REFUSE unless `--force`. `complete-init` finishes a *fresh* bootstrap; running it by mistake on a mature project could clobber its owned `.python-version` / `.claude/settings.local.json` / `ci.yml`.
   - **a fresh project clone with `.meta-version`** → proceed.

Once preflight passes, **delegate the rest to the `alemax-complete-init` skill** (`.claude/skills/alemax-complete-init/SKILL.md`).

---

## Context guard

This command requires the operator to be in a **bootstrapped project clone** (`context: project`), not the meta-repo and not an un-bootstrapped repo. The skill body's Step 0 enforces this.

Skill declared context: `project` (per `.claude/skills/alemax-complete-init/SKILL.md` frontmatter, codified in `openspec/specs/alemax-skills/spec.md`). This is the first `context: project` skill in the family.

---

## Input

The argument after `/alemax:complete-init` is optional:

- **No args** — default: state-driven walkthrough of every completion phase.
- **`--dry-run`** — enumerate what each phase would do; perform no mutations (no secrets prompt, no `remote set-head`, no file edits).
- **`--force`** — bypass the freshness gate (see below). Only needed if you deliberately want to run `complete-init` on an established, long-running project.

Examples:

```
/alemax:complete-init
/alemax:complete-init --dry-run
```

## Behavior overview

1. **Phase 1 — Detect stack + state** (python/go/bash; read `.meta-version`).
2. **Phase 2 — Keychain secrets** (`bin/set-secret.sh --list` → offer `--bootstrap`, interactive).
3. **Phase 3 — `origin/HEAD`** (`git remote set-head origin --auto` if unset — fixes `/security`).
4. **Phase 4 — GH Actions secrets** (advisory; the `sync-secrets-to-gh.sh` bridge is meta-side).
5. **Phase 5 — Fresh-bootstrap hygiene** (from smoke-test-3: `.python-version`, seed `.claude/settings.local.json` **before the first merge** (never a tracked `settings.json`), cross-stack `ci.yml` trim — detect + offer fix).
6. **Phase 6 — Go-stack post-generate** (go only: `make manifests generate`, rename sample API, first image build).
7. **Phase 7 — Verify** (pre-commit; run tests; **propose `/doctor`, `/test`, `/security`**; best-effort CI status).
8. **Phase 8 — First real change** (guide the operator's first change → commit → push → open PR → **merge**; the Phase-5 `.claude/settings.local.json` makes the merge work).
9. **Phase 9 — Bootstrap nudge removal** (only **after** the first real change has merged, drop the `CLAUDE.md` nudge).
10. **Phase 10 — Summary + next step** (`/opsx:propose` for the next change).

Full procedure in `.claude/skills/alemax-complete-init/SKILL.md`.

## When NOT to use this skill

- **You want to CREATE a project** — use `/alemax:new-project` from the meta-repo. This skill finishes one that already exists.
- **You're retrofitting an existing (non-bootstrapped) repo** — that's `retrofit-project.sh`, meta-side.
- **You're in the meta-repo** — the skill refuses.

## Cross-links

- `.claude/skills/alemax-complete-init/SKILL.md` — full skill body.
- `.claude/commands/alemax/new-project.md` — meta-side producer that creates the project.
- `.claude/commands/alemax/complete-update.md` — sibling: finishes a template *update* from the project side.
- `openspec/specs/project-side-completion/spec.md` — capability spec.
- `openspec/specs/alemax-skills/spec.md` — family conventions + `context` enforcement.

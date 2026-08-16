---
name: "ALEMAX: New project"
description: Bootstrap a new project in the operator's fork-managed claude-meta workflow. Conversational wrapper around meta/bootstrap/init-project.sh.
category: Workflow
tags: [workflow, bootstrap, alemax]
---

<!-- Governance preamble — this skill is fork-divergent-only; no canonical-only mutation -->

## Governance preamble (run BEFORE any other step)

This command mutates only **fork-divergent** state — `projects.yaml` and `repos.yaml` are both fork-divergent per [[empty-canonical-projects-yaml]] and [[empty-canonical-repos-yaml]]; entries live as direct commits on the operator's current `aiml0NN` per-drive branch. The canonical-only rule ([[openspec-governance-canonical-only]]) does not bite here — there is no canonical PR to open.

Before doing anything else:

1. Run `git remote get-url origin` and `git branch --show-current`.
2. Apply the decision matrix:
   - **origin contains `alemaxdesign/claude-meta` AND branch = `main`** → REFUSE. Canonical's `main` is not where new-project commits land. Operator should `cd` to their fork clone and `git checkout aiml0NN` first.
   - **origin is a fork AND branch matches `^aiml[0-9]{2}$`** → proceed. This is the expected case — the skill's `projects.yaml` and `repos.yaml` commits will land here.
   - **origin is a fork AND branch = `main`** → REFUSE with the actionable hint: "Switch to your aiml0NN branch before invoking this skill — `git checkout aiml0NN`."
   - **any other branch (feature branch, detached HEAD)** → REFUSE with the same hint. The skill body's Step 0 enforces this anyway; the slash-command preamble is the cheap first pass.
3. Verify working tree is clean (`git status --porcelain` is empty). If not, ask the operator to stash or commit pending changes first.

Once the preflight passes, **delegate the rest of the flow to the `alemax-new-project` skill** (`.claude/skills/alemax-new-project/SKILL.md`). The skill owns the conversational arg-gathering, validation, confirmation, invocation, and reporting. The skill's own Step 0 + Step 1 enforce the same branch + fork-sync invariants as load-bearing defense in depth.

---

## Context guard

This command requires the operator to be in their **claude-meta clone** (meta-repo), not a downstream project. The skill body's Step 0 verifies this and refuses on mismatch. If you're seeing this skill listed from a project clone session (post-`ship-alemax-skills-in-projects`), `cd` to your meta-repo clone first.

Skill declared context: `claude-meta-only` (per `.claude/skills/alemax-new-project/SKILL.md` frontmatter, codified in `openspec/specs/alemax-skills/spec.md`).

---

## Input

The argument after `/alemax:new-project` is one of:

- **Nothing** (operator just typed `/alemax:new-project`) — delegate to the skill's full conversational flow.
- **A description** (free-form, e.g., `/alemax:new-project "CLI for sorting downloads"`) — pass to the skill; it'll parse + ask the unknowns.
- **Positional args** (power-user shortcut: `/alemax:new-project <name> <stack> <ghhandle> <description>`) — parse + present the plan; the skill still requires explicit confirmation before invoking.

## Behavior

Read the operator's input. If it's positional shorthand, parse the four args directly. Otherwise, hand off to the skill.

Either way, the skill's flow (the 8 steps documented in `.claude/skills/alemax-new-project/SKILL.md`) is non-negotiable:

1. Preflight (incl. fork-sync check: refuses if `main` is behind `upstream/main`, or `aiml0NN` is behind `main`)
2. Gather args
3. Validate
4. Present the plan
5. Confirm explicitly
6. Invoke `meta/bootstrap/init-project.sh`
7. Post-bootstrap `repos.yaml` direct commit (on current `aiml0NN`, no canonical PR)
8. Report + next-step command

**Do not skip step 5 (explicit confirmation)** even when positional args are provided — positional input expresses the operator's intent, not their consent to side effects.

## Output

After the skill's step 8, the slash command itself adds nothing; the skill's final report is the output. The operator's next manual action is the `cd ... && claude` command surfaced in that report.

## See also

- `.claude/skills/alemax-new-project/SKILL.md` — the skill body (8-step flow)
- `meta/docs/ALEMAX-SKILLS.md` — the `/alemax:*` family convention
- `meta/bootstrap/init-project.sh` — the underlying script (12 phases)
- `[[openspec-governance-canonical-only]]` — the canonical-only rule this command respects

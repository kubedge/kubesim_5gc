---
name: alemax-diagnose
description: Scaffold a new diagnosis directory with the standardized 10-section template. Conversationally prompts for topic + scope + symptom + starting hypothesis; smart-defaults location based on current context (`openspec/diagnosis/` when in meta-repo, `.local/diagnosis/` when in project); operator may override. Matches the shape of existing diagnoses in `openspec/diagnosis/`.
license: MIT
compatibility: Requires bash, git. Honors `dot-local-scratch-convention` (`.local/` gitignored) when writing operator-local diagnoses. The second `/alemax:*` skill with `context: either` — works from meta-repo OR project clones.
context: either
metadata:
  author: alemax
  version: "1.0"
---

## Wraps

No single shell script. The workflow is: ask where to write, prompt the operator for 4 fields, scaffold a `diagnosis.md` populated with the template + operator-supplied values, hand off for conversational fill-in.

This skill is the cousin of `/alemax:feedback`: feedback is for one-line friction notes; diagnose is for deeper investigations that warrant a full template + multi-session work. Matches the shape of the two existing examples in `openspec/diagnosis/`.

## The diagnosis-doc story

Some operator findings are bigger than a feedback row. The 2026-05-29 brand-new-operator fork test and the 2026-05-31 claude-keychain-on-AIML drive diagnoses both run multiple pages of empirical findings + root-cause analysis + design implications. They live under `openspec/diagnosis/<date>-<topic>/diagnosis.md` and follow a stable 10-section structure.

`/alemax:diagnose` scaffolds that structure so the operator doesn't have to remember it. Smart-default location matches the conventional case (meta-repo → committed `openspec/diagnosis/`; project → operator-local `.local/diagnosis/`); operator overrides explicitly.

## Behavior overview

1. **Step 0 — Context check.** Detect meta-repo vs project. Don't refuse; branch only on default location.
2. **Step 1 — Location prompt** with smart default + alternative. Operator confirms or overrides.
3. **Step 2 — Topic slug prompt** (kebab-case lowercase; validate + re-prompt on invalid).
4. **Step 3 — Scope, symptom, starting hypothesis prompts** (each free-form).
5. **Step 4 — Build the directory path** with collision handling (append `-2`, `-3`, …).
6. **Step 5 — Write `diagnosis.md`** populated with the standardized template + operator-supplied values.
7. **Step 6 — Confirm** with path; mention subsequent fill-in happens conversationally.

## Steps

### Step 0 — Context check (passes through, branches default)

```bash
CURRENT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ "$ORIGIN_URL" == *"claude-meta"* && "$CURRENT_ROOT" == *"/claude-meta" ]]; then
  CURRENT_CONTEXT="claude-meta"
  DEFAULT_LOC="openspec/diagnosis"
  ALT_LOC=".local/diagnosis"
else
  CURRENT_CONTEXT="project"
  DEFAULT_LOC=".local/diagnosis"
  ALT_LOC="openspec/diagnosis"
fi
```

### Step 1 — Location prompt

```
This diagnosis can live in:
  [d] <default-location>/   (default — recommended for current context: <current-context>)
  [a] <alt-location>/       (alternative)

Where? [d/a]
```

Capture choice. Default is `d` on blank.

### Step 2 — Topic slug

```
Topic slug? (kebab-case lowercase, e.g. docker-auth-loop)
```

Validate against `^[a-z][a-z0-9-]*$`. On mismatch:

```
Invalid. Use kebab-case lowercase (start with letter, only a-z 0-9 and -).
```

…and re-prompt.

### Step 3 — Scope + Symptom + Hypothesis

```
One-line scope: <what does this diagnosis cover?>
Immediate symptom: <what's the observable failure or finding?>
Starting hypothesis: <what do you think is going on? (will be refined as you fill in)>
```

Capture each as `$SCOPE`, `$SYMPTOM`, `$HYPOTHESIS`.

### Step 4 — Build the path

```bash
DATE="$(date +%Y-%m-%d)"
# For openspec/diagnosis: <date>-<topic>; for .local/diagnosis: just <topic>
if [ "$CHOSEN_LOC" = "openspec/diagnosis" ]; then
  TARGET_DIR="$CURRENT_ROOT/openspec/diagnosis/$DATE-$TOPIC"
else
  TARGET_DIR="$CURRENT_ROOT/.local/diagnosis/$TOPIC"
fi

# Collision handling
N=2
ORIG_TARGET="$TARGET_DIR"
while [ -e "$TARGET_DIR" ]; do
  TARGET_DIR="$ORIG_TARGET-$N"
  N=$((N+1))
done
```

### Step 5 — Write `diagnosis.md` from template

```bash
mkdir -p "$TARGET_DIR"
OPERATOR="$(whoami)"
DRIVE_NUM="$(basename "$(readlink -f /Volumes/AIML0* 2>/dev/null | head -1)" 2>/dev/null | sed 's/AIML0//')"
DRIVE_FIELD=""
if [ -n "$DRIVE_NUM" ]; then
  DRIVE_FIELD="**Active drive:** AIML0$DRIVE_NUM"$'\n'
fi

cat > "$TARGET_DIR/diagnosis.md" <<DIAGNOSIS_EOF
# Diagnosis — $SYMPTOM

**Date:** $DATE
**Operator:** $OPERATOR
$DRIVE_FIELD

## TL;DR

<2-4 sentences. Refine as the diagnosis develops.>

Starting hypothesis: $HYPOTHESIS

## The scenario that triggered the diagnosis

**Scope:** $SCOPE

<Detailed context: what was the operator doing, what command produced what output, etc.>

## Empirical findings

<Observations from runs, command output, traced behavior, log excerpts.>

## Mechanism

<Root-cause analysis. What's actually happening under the hood?>

## Design re-examination

<Does this finding change any spec or assumption? Which capability is affected?>

## Findings table

| # | Finding | Severity | Resolution |
|---|---|---|---|
| 1 | <one-line> | blocker / friction / idea | <action / proposal> |

## Reproduction

<Minimal repro steps.>

\`\`\`bash
# commands here
\`\`\`

## Open questions

<What's not yet resolved? What needs an operator decision?>

## Next steps

<Follow-up changes to propose, ideas to capture, fixes to ship.>

## Cross-links

<Related specs, archived changes, sibling diagnoses, PRs.>
DIAGNOSIS_EOF
```

### Step 6 — Confirm

```
Scaffolded.
  Path:     <target-dir>/diagnosis.md
  Topic:    <topic>
  Scope:    <scope>

Next: fill in the sections conversationally. The template covers
  TL;DR / scenario / empirical findings / mechanism / design re-examination /
  findings table / reproduction / open questions / next steps / cross-links.
```

## Edge cases

- **Operator picks `openspec/diagnosis/` from a project clone** — skill writes to `$CURRENT_ROOT/openspec/diagnosis/` (the PROJECT's openspec dir, not the meta-repo's). Most likely the operator should `cd` to the meta-repo first; skill warns once and proceeds if confirmed.
- **`.local/` doesn't exist in the project** — `mkdir -p` handles it. (Per `dot-local-scratch-convention`, `init-project.sh` already creates `.local/` at bootstrap; older bootstrapped projects may not have it.)
- **Topic slug collides** — `-2`, `-3`, … per Step 4. Path is announced in Step 6.
- **Operator wants to skip a prompt** — `skip` for hypothesis is allowed (it's the most uncertain at start); the template just shows "Starting hypothesis: " with no content. Other fields are required.

## system-path-rule

This skill operates under either `openspec/` or `.local/` — both repo-relative. No macOS-system-rooted paths involved.

## Cross-links

- `openspec/diagnosis/README.md` — the diagnosis-dir convention this skill extends.
- `openspec/diagnosis/2026-05-29-brand-new-operator-fork-test/` and `openspec/diagnosis/2026-05-31-claude-keychain-on-aiml-drive/` — the two existing examples whose shape this skill matches.
- `openspec/specs/spec-governance/spec.md` — `.local/` convention.
- `openspec/specs/alemax-skills/spec.md` — `context: either` requirement.
- `.claude/skills/alemax-feedback/SKILL.md` — sibling skill; feedback rows can link to diagnoses created by this skill.

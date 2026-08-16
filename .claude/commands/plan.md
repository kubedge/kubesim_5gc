---
description: Break down a feature or task into concrete, file-level steps with a test plan.
---

# /plan

Use this when a task is too big to start coding immediately. Produce a numbered, executable plan that someone (or you in a future session) can follow without re-deriving context.

## Procedure

1. **Read context.** Read `CLAUDE.md`, then any files the task obviously touches. Don't read the whole repo — read what's needed to answer the question.
2. **Surface ambiguity.** If 2+ reasonable interpretations of the request exist, ask one clarifying question. Don't bury it; state the choices and pick a default.
3. **Decompose.** Produce a numbered list of steps. Each step:
   - Names the file(s) it touches.
   - Names the function/section/symbol being added or changed.
   - States the change in one sentence.
4. **Test plan.** End with a "How we'll know it works" section: which tests to add or run, what assertions matter, what manual check is needed (if any).
5. **Risks & deferrals.** One short section listing anything intentionally out of scope.

## Output shape

```
## Goal
<one sentence>

## Steps
1. file:path — change …
2. …

## Tests
- …

## Out of scope
- …
```

Keep it tight. A plan is a working tool, not a deliverable.

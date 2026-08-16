---
description: Triage a failure (test output, stack trace, log). Build a hypothesis tree.
---

# /debug

The user pastes (or points at) an error: a stack trace, failing test output, an application log. Your job is to make the failure smaller and more legible, not to immediately patch.

## Procedure

1. **Read the error closely.** What exception/exit code/assertion? What's the call site?
2. **State what's known and what's assumed.** Distinguish facts (this line raised X) from inferences (so probably Y).
3. **Build a hypothesis tree.**
   - Top hypothesis: most likely root cause given the evidence.
   - Alternates: 1–3 other plausible causes.
   - For each, name the experiment that would falsify it (a print, a test, a config check).
4. **Pick one experiment, run it.** Prefer the cheapest, most decisive one.
5. **Iterate** until a single hypothesis is left standing.
6. **Then** propose a fix — minimal, targeted, with a regression test.

## Anti-patterns to avoid

- Patching symptoms (catch + log + re-raise as a different exception is rarely a fix).
- "Refactoring while debugging" — don't conflate the two.
- Adding `try/except` to make a stack trace go away.
- Sleeping or retrying around a race without understanding it.

## When stuck

- Bisect: revert recent changes one at a time; the first reverted change that makes the bug disappear is likely the cause.
- Re-read the docs for the function that's misbehaving — assumptions about its contract are a common culprit.

---
description: Run tests; if they fail, propose fixes; if they're missing, generate them.
---

# /test

## Procedure

1. **Detect the runner.**
   - Python: `pyproject.toml` exists → `uv run pytest` (with whatever args are configured under `[tool.pytest.ini_options]`).
   - Bash: `tests/*.bats` exists → `bats tests/`.
   - Both: run both.
2. **Run.** Stream output; capture exit code.
3. **If green:** report pass count and any slow tests (>1s). Done.
4. **If red:**
   - For each failing test, show the failure (assertion, traceback) succinctly.
   - Form a hypothesis. Read the code under test before proposing a fix — failing tests are usually right and code is wrong, but not always.
   - Propose a minimal fix. Don't refactor surrounding code.
5. **If a feature has no test:**
   - Delegate to the `test-writer` subagent.
   - Cover happy path + 2–3 edge cases (empty/large/invalid input, error paths).
   - Don't write tautological tests (`assert mock.called_once`); test behavior.

## Style

- Pytest: prefer plain `assert`, parametrize over loops, use fixtures sparingly.
- Bats: keep tests under 20 lines; one assertion per test where reasonable.
- Never mock the system under test.
- Mock external I/O (network, filesystem) at the boundary, not in the middle.

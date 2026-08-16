---
description: Update README and inline docs to match the current state of the code.
---

# /docs

## Procedure

1. **Diff docs vs code.** Read README.md, CLAUDE.md, and any docs/ files. Note claims they make about: install, usage, public API, file layout, env vars, commands.
2. **Validate the claims.** For each claim, check the code:
   - Does the install command still work?
   - Are the CLI flags/subcommands still real?
   - Are the env vars/secrets list still accurate?
   - Has the file layout drifted?
3. **Delegate to `docs-writer`** for the rewrite. Aim for: concise, example-driven, no fluff. Cut sections that have aged out rather than padding around them.
4. **Show a diff** of proposed doc changes before writing.

## What good looks like

- README opens with one sentence answering "what is this and who is it for."
- A working "quick start" — copy/paste-able commands that actually work on a fresh checkout.
- Examples have real shape (real flag names, real outputs), not handwaved placeholders.
- CLAUDE.md has the conventions a future Claude session would actually need (test invocation, lint command, secrets pattern).

## What to cut

- "Roadmap" / "future work" sections that haven't been touched in months.
- Aspirational features described as if they exist.
- Tables of contents in short docs.
- Badges that don't link to live status.

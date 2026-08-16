---
description: Security pass. Delegates code analysis to the built-in /security-review; adds the secret + dependency scanning it does not cover.
---

# /security

Claude Code ships a built-in `/security-review` that performs LLM security analysis of the current branch's diff. It is product-maintained by Anthropic and improves on its own — **do not reimplement it here.** This command wraps it with the two things it deliberately does *not* do: working-tree secret scanning and dependency CVE auditing.

## Procedure

1. **Delegate the code analysis.** Invoke the built-in `security-review` skill. This is the primary pass — do not hand-roll a parallel diff review alongside it. (If it fails on a missing reference, `git remote set-head origin --auto` fixes it.)
2. **Secret scan** — built-in does not do this; it reads the diff, not the working tree. Run `gitleaks detect --no-banner --redact`. Zero hits is the bar.
3. **Dependency audit** — built-in does not do this at all.
   - Python: `uv run pip-audit` (or `uv pip audit` if available). Surface critical/high CVEs first.
   - Node tooling: `npm audit --omit=dev` if `package.json` exists.
4. **Optional deep pass.** To review the *whole repo* against this project's threat model rather than just the branch diff, delegate to the `security-scanner` subagent. Skip it for routine changes — `/security-review` already covers the diff.
5. **Report** in three buckets: 🚨 fix now, ⚠️ fix soon, 💡 hardening ideas. Fold the built-in's findings into these buckets rather than reporting them separately.

## Don't

- Don't duplicate `/security-review`'s code analysis by hand — it is maintained upstream and gets better without you.
- Don't auto-fix CVEs by bumping deps blindly — read the changelog for breaking changes first.
- Don't suggest installing unverified third-party scanners; stick to the ones in the meta-repo's CI baseline.

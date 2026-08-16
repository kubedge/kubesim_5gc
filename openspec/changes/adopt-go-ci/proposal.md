# Adopt the class-M Go CI

## Why

The repo builds/tests locally via raw `go` + the Makefile, but has no CI that runs on
push. claude-meta ships a class-M `.github/workflows/ci.yml` that auto-detects `go.mod`
and runs `go-build` / `go-vet` / `go-test -race` / `golangci-lint`, matching the local
verify loop. Adopting it makes green a gate, not a hope.

## What changes

- Deliver the class-M CI (via `/alemax:update-skills` broadcast → `/alemax:complete-update`)
  plus the rest of the class-M set (`.editorconfig`, `.gitattributes`, `.github/*`,
  `dependabot.yml`, `.pre-commit-config.yaml`, `bin/set-secret.sh`).
- Confirm the four Go jobs run and pass on a trial push.

## Non-goals

- Changing the Makefile targets (CI runs raw `go`, independent of the Makefile).

## Impact

Every future change is gated on build/vet/test/lint. Fleet-wide: identical for every
operator, so this change is a template.

## ADDED Requirements

### Requirement: The repo runs Go CI on every push

The repository SHALL carry the class-M `.github/workflows/ci.yml` that auto-detects
`go.mod` and runs `go-build`, `go-vet`, `go-test -race`, and `golangci-lint` as required
checks, so build/vet/test/lint green is enforced on every push independently of the
Makefile.

#### Scenario: CI gates a push
- **WHEN** a commit is pushed to a branch with `go.mod` present
- **THEN** the four Go jobs run and a failure blocks the change

## ADDED Requirements

### Requirement: The simulator pins the current kubesim_base tag consistently

This simulator SHALL require every `github.com/kubedge/kubesim_base/<module>` it uses at
the same current sim-base tag (realigned from its stale pin), consistent after
`go mod tidy`.

#### Scenario: sub-module pins are consistent
- **WHEN** `go.mod` is inspected after realign
- **THEN** all kubesim_base requires share the same new tag and `go build ./...` is green

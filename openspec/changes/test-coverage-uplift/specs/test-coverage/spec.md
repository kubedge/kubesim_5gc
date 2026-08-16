## ADDED Requirements

### Requirement: The simulator's core logic is unit-tested

This simulator SHALL have unit tests covering its core message-handling / simulation
logic, run under `go test ./... -race`.

#### Scenario: the simulator has passing tests
- **WHEN** `go test ./... -race` runs
- **THEN** its core packages have passing tests (no longer 0 coverage)

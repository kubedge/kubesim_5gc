## ADDED Requirements

### Requirement: Sim-base modules target a current Go toolchain

Every sim-base module (`config`, `connected`, `grpc/go`, and root/health/arpscan) SHALL
declare a current, supported `go` directive (raised from `go 1.20`), and each module SHALL
build/vet/test green after `go mod tidy`.

#### Scenario: modules build on the bumped toolchain
- **WHEN** `go build ./... && go test ./... -race` runs in each module after the bump
- **THEN** they pass, and no module still declares the stale `go 1.20`/`1.15` line

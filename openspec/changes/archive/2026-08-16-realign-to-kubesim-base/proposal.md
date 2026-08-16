# Realign to the current kubesim_base

## Why

This simulator pins `kubesim_base` sub-modules at a stale tag (the fleet splits across
`v0.1.24` and `v0.1.20`) and sits on an old `go` line. Once `kubesim_base` cuts its next
multi-module tag, this consumer must realign every kubesim_base require it uses to that
tag in one move.

## What Changes

- `go get` each consumed `kubesim_base/<module>` (this repo uses some subset of
  `config` / `connected` / `grpc/go`) to the new sim-base tag; then `go mod tidy`.
- Fix any breakage; keep `go build ./... && go vet ./... && go test ./...` green.

## Capabilities

### Modified Capabilities
- base-dependency: the pinned kubesim_base sub-module versions.

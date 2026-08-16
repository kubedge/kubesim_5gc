# Tasks — go-version-bump

- [ ] Decide the target go line (align with the operator side where practical).
- [ ] Raise the `go` directive in each module go.mod (config, connected, grpc/go, health, arpscan, root).
- [ ] `go mod tidy` per module; fix any breakage from the bump.
- [ ] `go build ./... && go vet ./... && go test ./... -race` green in each module.
- [ ] Sequence with `multimodule-tag-realign` (bump then re-tag together).

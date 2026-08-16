# Tasks — realign-to-kubesim-base

- [ ] Wait for `kubesim_base` to publish the new tag (its multimodule-tag-realign change).
- [ ] `go get` each kubesim_base sub-module this repo requires (`config` and/or `connected`/`grpc/go`) at the new `<tag>`.
- [ ] `go mod tidy`; confirm every kubesim_base require moved to `<tag>`.
- [ ] `go build ./... && go vet ./... && go test ./... -race` green.

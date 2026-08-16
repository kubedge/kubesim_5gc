# Tasks — realign-to-kubesim-base

- [x] Wait for `kubesim_base` to publish the new tag (its multimodule-tag-realign change). — v0.1.25 published.
- [x] `go get` each kubesim_base sub-module this repo requires (`config` and/or `connected`/`grpc/go`) at the new `<tag>`. — config/connected/grpc/go @v0.1.25.
- [x] `go mod tidy`; confirm every kubesim_base require moved to `<tag>`. — all three at v0.1.25; go directive folded 1.20 -> 1.26.0.
- [x] `go build ./... && go vet ./... && go test ./... -race` green. — verified (root `cmd/` collision -> `go build -o /dev/null ./...`).

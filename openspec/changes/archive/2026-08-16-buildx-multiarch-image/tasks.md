# Tasks — buildx-multiarch-image

- [x] Confirm buildx + a running builder (colima on Apple-Silicon). — colima `multiarch` docker-container builder (linux/arm64 + amd64).
- [x] For each built image, add a buildx target `docker buildx build --platform linux/arm64 -t <image>:<tag>` (add `,linux/amd64` only if still needed). — Makefile `docker-buildx` (PLATFORMS=linux/arm64,linux/amd64).
- [x] Make each Dockerfile multi-stage (compile per TARGETOS/TARGETARCH; don't copy a prebuilt amd64 binary). — build/Dockerfile.buildkit: `FROM --platform=$BUILDPLATFORM golang:1.26`, cross-compiles via GOARCH; final `FROM scratch`.
- [x] Remove the `_AMD64/_ARM64V8/_ARM32V7` image-name variables. — retired (commented out) alongside the per-arch build/push targets.
- [x] `docker buildx imagetools inspect` each image → manifest list incl. linux/arm64. — verified via local OCI export (no push): manifest list sha256:1a2ae76e… includes linux/arm64 + linux/amd64.
- [ ] If deployed by an operator, update that operator's example CR to the arch-independent name. — N/A: single-binary sim, not operator-deployed.

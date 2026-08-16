# Buildx multi-arch image(s)

## Why

The Makefile builds this simulator's image(s) with the architecture baked into the name
(`_DEV/_AMD64/_ARM64V8/_ARM32V7` variants). The real target is arm64 (Apple-Silicon dev +
Pi armv8). `docker buildx` produces one multi-arch image per built artifact under a single
name:tag, and the runtime resolves the arch — collapsing the arch-suffixed variants (and,
for sims deployed by an operator, the operator's per-arch example CRs).

## What Changes

- For each image this repo builds, add a `docker buildx build --platform
  linux/arm64[,linux/amd64] -t <image>:<tag>` target; ensure each Dockerfile is
  multi-stage (compiles per TARGETOS/TARGETARCH).
- Drop the `_AMD64/_ARM64V8/_ARM32V7` image-name variants (one name per artifact).

## Capabilities

### New Capabilities
- container-packaging: how this simulator's image(s) are built.

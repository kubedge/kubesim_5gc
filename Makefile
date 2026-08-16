
# Image URL to use all building/pushing image targets
COMPONENT        ?= kubesim_5gc
VERSION          ?= 0.2.20
DHUBREPO         ?= hack4easy/${COMPONENT}
DOCKER_NAMESPACE ?= hack4easy

# Arch-independent image tag — one multi-arch manifest list, produced by the
# `docker-buildx` path below.
IMG              ?= ${DHUBREPO}:v${VERSION}
K8S_NAMESPACE    ?= default

# RETIRED: superseded by docker-buildx — the arch-suffixed (-dev/-amd64/
# -arm64v8/-arm32v7) repos + image tags are replaced by the single
# arch-independent IMG above (buildx emits one multi-arch manifest list).
# DHUBREPO_DEV     ?= hack4easy/${COMPONENT}-dev
# DHUBREPO_AMD64   ?= hack4easy/${COMPONENT}-amd64
# DHUBREPO_ARM32V7 ?= hack4easy/${COMPONENT}-arm32v7
# DHUBREPO_ARM64V8 ?= hack4easy/${COMPONENT}-arm64v8
# IMG_DEV          ?= ${DHUBREPO_DEV}:${VERSION}
# IMG_AMD64        ?= ${DHUBREPO_AMD64}:${VERSION}
# IMG_ARM32V7      ?= ${DHUBREPO_ARM32V7}:${VERSION}
# IMG_ARM64V8      ?= ${DHUBREPO_ARM64V8}:${VERSION}

# CONTAINER_TOOL defines the container tool to be used for building images.
# Be aware that the target commands are only tested with Docker which is
# scaffolded by default. However, you might want to replace it to use other
# tools. (i.e. podman)
CONTAINER_TOOL ?= docker

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

# docker-buildx is the sole go-forward image path: one multi-arch manifest
# list, built from build/Dockerfile.buildkit (which pins
# `FROM --platform=$$BUILDPLATFORM` and cross-compiles via GOARCH).
all: docker-buildx

setup:
ifndef GOPATH
	$(error GOPATH not defined, please define GOPATH. Run "go help gopath" to learn more about GOPATH)
endif
	# dep ensure

clean:
	rm -fr vendor
	rm -fr cover.out
	rm -fr build/_output
	rm -fr config/crds
	rm -fr go.sum

# Run go fmt against code
fmt: setup
	go fmt ./cmd/...

# Run go vet against code
vet: fmt
	go vet -composites=false ./cmd/...

# ---------------------------------------------------------------------------
# Cross-platform multi-arch image (buildx) — THE go-forward path.
# Drives build/Dockerfile.buildkit directly. The Dockerfile already pins the
# builder to $$BUILDPLATFORM and cross-compiles (CGO_ENABLED=0,
# GOARCH=$$TARGETARCH), so no per-arch emulation is needed.
# Requires a live buildx builder (e.g. `colima start` on Apple Silicon).
# NOTE: buildx pushes multi-arch manifests directly (can't --load a manifest
# list), so this target --push. arm/v7 retired from the default PLATFORMS
# (validated on arm64+amd64); re-add `,linux/arm/v7` if needed.
# ---------------------------------------------------------------------------
PLATFORMS ?= linux/arm64,linux/amd64

.PHONY: docker-buildx
docker-buildx: fmt vet ## Build and push the multi-arch kubesim_5gc image
	$(CONTAINER_TOOL) buildx build --push --platform=$(PLATFORMS) -t ${IMG} -f build/Dockerfile.buildkit .

# Run against the configured Kubernetes cluster in ~/.kube/config
install:
	helm install kubesim-lte charts/kubesim-lte --set images.tags.operator=${IMG} --namespace ${K8S_NAMESPACE}

purge:
	helm uninstall kubesim-lte --namespace ${K8S_NAMESPACE}

# ===========================================================================
# RETIRED: superseded by docker-buildx.
# The per-variant (dev / amd64 / arm32v7 / arm64v8) single-arch build + push
# targets below drove the plain + per-arch Dockerfiles (build/Dockerfile.amd64
# / .arm32v7 / .arm64v8). They are kept commented (not deleted) for reference
# and rollback. The go-forward path is the buildx section above.
# The per-arch install targets referenced per-arch charts that no longer exist
# (only charts/kubesim-lte remains); retired alongside.
# ===========================================================================
#
# docker-build: fmt vet docker-build-dev docker-build-amd64 docker-build-arm32v7 docker-build-arm64v8
#
# docker-build-dev:
# 	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o build/_output/bin/goserv -gcflags all=-trimpath=${GOPATH} -asmflags all=-trimpath=${GOPATH} -tags=v1 ./cmd/...
# 	docker build . -f build/Dockerfile.dev -t ${IMG_DEV}
# 	docker tag ${IMG_DEV} ${DHUBREPO_DEV}:latest
#
# docker-build-amd64:
# 	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o build/_output/amd64/goserv -gcflags all=-trimpath=${GOPATH} -asmflags all=-trimpath=${GOPATH} -tags=v1 ./cmd/...
# 	docker build . -f build/Dockerfile.amd64 -t ${IMG_AMD64}
# 	docker tag ${IMG_AMD64} ${DHUBREPO_AMD64}:latest
#
# docker-build-arm32v7:
# 	GOOS=linux GOARM=7 GOARCH=arm CGO_ENABLED=0 go build -o build/_output/arm32v7/goserv -gcflags all=-trimpath=${GOPATH} -asmflags all=-trimpath=${GOPATH} -tags=v1 ./cmd/...
# 	docker build . -f build/Dockerfile.arm32v7 -t ${IMG_ARM32V7}
# 	docker tag ${IMG_ARM32V7} ${DHUBREPO_ARM32V7}:latest
#
# docker-build-arm64v8:
# 	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o build/_output/arm64v8/goserv -gcflags all=-trimpath=${GOPATH} -asmflags all=-trimpath=${GOPATH} -tags=v1 ./cmd/...
# 	docker build . -f build/Dockerfile.arm64v8 -t ${IMG_ARM64V8}
# 	docker tag ${IMG_ARM64V8} ${DHUBREPO_ARM64V8}:latest
#
# docker-push: docker-push-dev docker-push-amd64 docker-push-arm32v7 docker-push-arm64v8
# docker-push-dev:
# 	docker push ${IMG_DEV}
# docker-push-amd64:
# 	docker push ${IMG_AMD64}
# docker-push-arm32v7:
# 	docker push ${IMG_ARM32V7}
# docker-push-arm64v8:
# 	docker push ${IMG_ARM64V8}
#
# --- Retired per-arch install targets (referenced non-existent per-arch charts) ---
# install: install-dev
# install-dev: docker-build-dev
# 	helm install --name kubesim-lte charts/kubesim-lte-dev --set images.tags.operator=${IMG_DEV} --namespace ${K8S_NAMESPACE}
# install-amd64:
# 	helm install --name kubesim-lte charts/kubesim-lte-amd64 --set images.tags.operator=${IMG_AMD64},images.pull_policy=Always --namespace ${K8S_NAMESPACE}
# install-arm32v7:
# 	helm install --name kubesim-lte charts/kubesim-lte-arm32v7 --set images.tags.operator=${IMG_ARM32V7},images.pull_policy=Always --namespace ${K8S_NAMESPACE}
# install-arm64v8:
# 	helm install --name kubesim-lte charts/kubesim-lte-arm64v8 --set images.tags.operator=${IMG_ARM64V8},images.pull_policy=Always --namespace ${K8S_NAMESPACE}

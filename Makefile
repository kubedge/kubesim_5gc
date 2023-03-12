
# Image URL to use all building/pushing image targets
COMPONENT        ?= kubesim_5gc
VERSION_V1       ?= 0.1.24
DHUBREPO_DEV     ?= hack4easy/${COMPONENT}-dev
DHUBREPO_AMD64   ?= hack4easy/${COMPONENT}-amd64
DHUBREPO_ARM32V7 ?= hack4easy/${COMPONENT}-arm32v7
DHUBREPO_ARM64V8 ?= hack4easy/${COMPONENT}-arm64v8
DOCKER_NAMESPACE ?= hack4easy
IMG_DEV          ?= ${DHUBREPO_DEV}:${VERSION_V1}
IMG_AMD64        ?= ${DHUBREPO_AMD64}:${VERSION_V1}
IMG_ARM32V7      ?= ${DHUBREPO_ARM32V7}:${VERSION_V1}
IMG_ARM64V8      ?= ${DHUBREPO_ARM64V8}:${VERSION_V1}
K8S_NAMESPACE    ?= default

all: docker-build

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
vet-v1: fmt
	go vet -composites=false -tags=v1 ./cmd/...

# Build the docker image
docker-build: fmt vet-v1 docker-build-dev docker-build-amd64 docker-build-arm32v7 docker-build-arm64v8

docker-build-dev:
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o build/_output/bin/goserv -gcflags all=-trimpath=${GOPATH} -asmflags all=-trimpath=${GOPATH} -tags=v1 ./cmd/...
	docker build . -f build/Dockerfile -t ${IMG_DEV}
	docker tag ${IMG_DEV} ${DHUBREPO_DEV}:latest

docker-build-amd64:
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o build/_output/amd64/goserv -gcflags all=-trimpath=${GOPATH} -asmflags all=-trimpath=${GOPATH} -tags=v1 ./cmd/...
	docker build . -f build/Dockerfile.amd64 -t ${IMG_AMD64}
	docker tag ${IMG_AMD64} ${DHUBREPO_AMD64}:latest

docker-build-arm32v7:
	GOOS=linux GOARM=7 GOARCH=arm CGO_ENABLED=0 go build -o build/_output/arm32v7/goserv -gcflags all=-trimpath=${GOPATH} -asmflags all=-trimpath=${GOPATH} -tags=v1 ./cmd/...
	docker build . -f build/Dockerfile.arm32v7 -t ${IMG_ARM32V7}
	docker tag ${IMG_ARM32V7} ${DHUBREPO_ARM32V7}:latest

docker-build-arm64v8:
	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o build/_output/arm64v8/goserv -gcflags all=-trimpath=${GOPATH} -asmflags all=-trimpath=${GOPATH} -tags=v1 ./cmd/...
	docker build . -f build/Dockerfile.arm64v8 -t ${IMG_ARM64V8}
	docker tag ${IMG_ARM64V8} ${DHUBREPO_ARM64V8}:latest

# Push the docker image
docker-push: docker-push-dev docker-push-amd64 docker-push-arm32v7 docker-push-arm64v8

docker-push-dev:
	docker push ${IMG_DEV}

docker-push-amd64:
	docker push ${IMG_AMD64}

docker-push-arm32v7:
	docker push ${IMG_ARM32V7}

docker-push-arm64v8:
	docker push ${IMG_ARM64V8}

# Run against the configured Kubernetes cluster in ~/.kube/config
install: install-dev

install-dev: docker-build-dev
	helm install --name kubesim-5gc charts/kubesim-5gc-dev --set images.tags.operator=${IMG_DEV} --namespace ${K8S_NAMESPACE}

install-amd64:
	helm install --name kubesim-5gc charts/kubesim-5gc-amd64 --set images.tags.operator=${IMG_AMD64},images.pull_policy=Always --namespace ${K8S_NAMESPACE}

install-arm32v7:
	helm install --name kubesim-5gc charts/kubesim-5gc-arm32v7 --set images.tags.operator=${IMG_ARM32V7},images.pull_policy=Always --namespace ${K8S_NAMESPACE}

install-arm64v8:
	helm install --name kubesim-5gc charts/kubesim-5gc-arm64v8 --set images.tags.operator=${IMG_ARM64V8},images.pull_policy=Always --namespace ${K8S_NAMESPACE}

purge: setup
	helm delete --purge kubesim-5gc

#!/bin/bash -x
export DHUBREPO="hack4easy/kubesim_5gc-arm32v7"
export VERSION="0.1.0"
export DOCKER_NAMESPACE="hack4easy"
export DOCKER_USERNAME="kubedgedevops"
export DOCKER_PASSWORD=$KUBEDGEDEVOPSPWD
cd kubesim_5gc
CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o goserv .
cd ..
echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
docker build -t $DHUBREPO:$VERSION -f images/kubesim_5gc/Dockerfile .
docker images
docker tag $DHUBREPO:$VERSION $DHUBREPO:latest
docker tag $DHUBREPO:$VERSION $DHUBREPO:from-master-pi
docker push $DHUBREPO

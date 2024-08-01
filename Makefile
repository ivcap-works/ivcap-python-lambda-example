SERVICE_NAME=chat-with-eliza
SERVICE_TITLE=Chat with Eliza

SERVICE_FILE=lambda.py

PROVIDER_NAME=ivcap.tutorial

LOCAL_DOCKER_REGISTRY=localhost:5000
K8S_DOCKER_REGISTRY=registry.default.svc.cluster.local
GCP_DOCKER_REGISTRY=australia-southeast1-docker.pkg.dev/reinvent-science-prod-2ae1/ivcap-service
DOCKER_REGISTRY=${GCP_DOCKER_REGISTRY}

SERVICE_ID:=ivcap:service:$(shell python3 -c 'import uuid; print(uuid.uuid5(uuid.NAMESPACE_DNS, \
        "${PROVIDER_NAME}" + "${SERVICE_CONTAINER_NAME}"));'):${SERVICE_CONTAINER_NAME}

GIT_COMMIT := $(shell git rev-parse --short HEAD)
GIT_TAG := $(shell git describe --abbrev=0 --tags ${TAG_COMMIT} 2>/dev/null || true)
GOOS=$(shell go env GOOS)
GOARCH=$(shell go env GOARCH)

DOCKER_USER="$(shell id -u):$(shell id -g)"

DOCKER_DOMAIN=$(shell echo ${PROVIDER_NAME} | sed -E 's/[-:]/_/g')
DOCKER_NAME=$(shell echo ${SERVICE_NAME} | sed -E 's/-/_/g')
DOCKER_VERSION=${GIT_COMMIT}
DOCKER_TAG=${DOCKER_DOMAIN}/${DOCKER_NAME}:${DOCKER_VERSION}
DOCKER_TAG_LOCAL=${DOCKER_NAME}:latest
ifeq ($(DOCKER_REGISTRY),)
# looks like docker-desktop deployment
DOCKER_DEPLOY=${DOCKER_TAG}
else
DOCKER_DEPLOY=$(DOCKER_REGISTRY)/${DOCKER_TAG}
endif

PROJECT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
TMP_DIR=/tmp
DOCKER_LOCAL_DATA_DIR=/tmp/DATA

GITHUB_USER_HOST?=git@github.com
SDK_CLONE_RELATIVE=.ivcap-sdk-python
SDK_CLONE_ABSOLUTE=${PROJECT_DIR}/.ivcap-sdk-python
SDK_COMMIT?=HEAD

# Check if DOCKER_REGISTRY is set to LOCAL_DOCKER_REGISTRY.
# If true, set TARGET_PLATFORM to linux/${GOARCH} to build for the local architecture.
# If false, set TARGET_PLATFORM to linux/amd64 as a default target platform.
ifeq ($(DOCKER_REGISTRY), $(LOCAL_DOCKER_REGISTRY))
TARGET_PLATFORM := linux/${GOARCH}
else
TARGET_PLATFORM := linux/amd64
endif

run:
	fastapi dev ${SERVICE_FILE}

build:
	poetry install

docker-run: #docker-build
	@echo ""
	@echo ">>>>>>> On Mac, please ensure that this directory is mounted into minikube (if that's what you are using)"
	@echo ">>>>>>>    minikube mount ${PROJECT_DIR}:${PROJECT_DIR}"
	@echo ""
	mkdir -p ${PROJECT_DIR}/DATA/run && rm -rf ${PROJECT_DIR}/DATA/run/*
	docker run -it \
		-e IVCAP_INSIDE_CONTAINER="" \
		-e IVCAP_ORDER_ID=ivcap:order:0000 \
		-e IVCAP_NODE_ID=n0 \
		-v ${PROJECT_DIR}:/data/in \
		-v ${PROJECT_DIR}/DATA/run:/data/out \
		-v ${PROJECT_DIR}/DATA/run:/app/cache \
		--user ${DOCKER_USER} \
		${DOCKER_NAME} \
		--msg "$(shell date "+%d/%m-%H:%M:%S")" \
		--background-img ${IMG_URL} \
		--ivcap:out-dir /app/cache
	@echo ">>> Output should be in '${DOCKER_LOCAL_DATA_DIR}' (might be inside minikube)"

docker-run-nuitka:
	make DOCKER_NAME=simple_python_service-nuitka docker-run

docker-debug: #docker-build
	# If running Minikube, the 'data' directory needs to be created inside minikube
	mkdir -p ${DOCKER_LOCAL_DATA_DIR}/in ${DOCKER_LOCAL_DATA_DIR}/out
	docker run -it \
		-e IVCAP_INSIDE_CONTAINER="" \
		-e IVCAP_ORDER_ID=ivcap:order:0000 \
		-e IVCAP_NODE_ID=n0 \
		-v ${PROJECT_DIR}:/data\
		--entrypoint bash \
		${DOCKER_NAME}

docker-build:
	@echo "Building docker image ${DOCKER_NAME}"
	docker build \
		-t ${DOCKER_TAG} \
		--platform=${TARGET_PLATFORM} \
		--build-arg GIT_COMMIT=${GIT_COMMIT} \
		--build-arg GIT_TAG=${GIT_TAG} \
		--build-arg BUILD_DATE="$(shell date)" \
		-f ${PROJECT_DIR}/Dockerfile \
		${PROJECT_DIR} ${DOCKER_BILD_ARGS}
	@echo "\nFinished building docker image ${DOCKER_NAME}\n"

docker-build-nuitka:
	@echo "Building docker image ${DOCKER_NAME}"
	docker build \
		--build-arg GIT_COMMIT=${GIT_COMMIT} \
		--build-arg GIT_TAG=${GIT_TAG} \
		--build-arg BUILD_DATE="$(shell date)" \
		-t ${DOCKER_NAME}-nuitka \
		-f ${PROJECT_DIR}/Dockerfile.nuitka \
		${PROJECT_DIR} ${DOCKER_BILD_ARGS}
	@echo "\nFinished building docker image ${DOCKER_NAME}\n"

SERVICE_IMG := ${DOCKER_DEPLOY}
PUSH_FROM := ""

docker-publish:
	@echo "Building docker image ${DOCKER_NAME}"
	@echo "====> DOCKER_REGISTRY is ${DOCKER_REGISTRY}"
	@echo "====> DOCKER_TAG is ${DOCKER_TAG}"
	docker tag ${DOCKER_TAG_LOCAL} ${DOCKER_DEPLOY}

	@$(eval size:=$(shell docker inspect ${DOCKER_TAG} --format='{{.Size}}' | tr -cd '0-9'))
	@$(eval imageSize:=$(shell expr ${size} + 0 ))
	@echo "ImageSize is ${imageSize}"
	@if [ ${imageSize} -gt 2000000000 ]; then \
		set -e ; \
		echo "preparing upload from local registry"; \
		if [ -z "$(shell docker ps -a -q -f name=registry-2)" ]; then \
			echo "running local registry-2"; \
			docker run --restart always -d -p 8081:5000 --name registry-2 registry:2 ; \
		fi; \
		docker tag ${DOCKER_TAG} localhost:8081/${DOCKER_TAG} ; \
		docker push localhost:8081/${DOCKER_TAG} ; \
		$(MAKE) PUSH_FROM="localhost:8081/" docker-publish-common ; \
	else \
		$(MAKE) PUSH_FROM="--local " docker-publish-common; \
	fi

docker-publish-common:
	@$(eval log:=$(shell ivcap package push --force ${PUSH_FROM}${DOCKER_TAG} | tee /dev/tty))
	@$(eval registry := $(shell echo ${DOCKER_REGISTRY} | cut -d'/' -f1))
	@$(eval SERVICE_IMG := $(shell echo ${log} | sed -E "s/.*(${registry}.*) pushed.*/\1/"))
	@if [ ${SERVICE_IMG} == "" ] || [ ${SERVICE_IMG} == ${DOCKER_DEPLOY} ]; then \
		echo "service package push failed"; \
		exit 1; \
	fi

service-description:
	env IVCAP_SERVICE_ID=${SERVICE_ID} \
		IVCAP_PROVIDER_ID=$(shell ivcap context get provider-id) \
		IVCAP_ACCOUNT_ID=$(shell ivcap context get account-id) \
		IVCAP_CONTAINER=${SERVICE_IMG} \
	python ${SERVICE_FILE} --ivcap:print-service-description

service-register: docker-publish
	env IVCAP_SERVICE_ID=${SERVICE_ID} \
		IVCAP_PROVIDER_ID=$(shell ivcap context get provider-id) \
		IVCAP_ACCOUNT_ID=$(shell ivcap context get account-id) \
		IVCAP_CONTAINER=${SERVICE_IMG} \
	python ${SERVICE_FILE} --ivcap:print-service-description \
	| ivcap service update --create ${SERVICE_ID} --format yaml -f - --timeout 600

clean:
	rm -rf ${PROJECT_DIR}/$(shell echo ${SERVICE_FILE} | cut -d. -f1 ).dist
	rm -rf ${PROJECT_DIR}/$(shell echo ${SERVICE_FILE} | cut -d. -f1 ).build
	rm -rf ${PROJECT_DIR}/cache ${PROJECT_DIR}/DATA


FORCE:

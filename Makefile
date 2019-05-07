RELEASE_NAME ?= p4-landing
CHART_VERSION ?= 0.3.0-beta1

SHELL := /bin/bash

NAMESPACE ?= default

DEV_CLUSTER ?= p4-development
DEV_PROJECT ?= planet-4-151612
DEV_ZONE ?= us-central1-a

PROD_CLUSTER ?= planet4-production
PROD_PROJECT ?= planet4-production
PROD_ZONE ?= us-central1-a

SED_MATCH ?= [^a-zA-Z0-9._-]
ifeq ($(CIRCLECI),true)
# Configure build variables based on CircleCI environment vars
BUILD_NUM = build-$(CIRCLE_BUILD_NUM)
BRANCH_NAME ?= $(shell sed 's/$(SED_MATCH)/-/g' <<< "$(CIRCLE_BRANCH)")
BUILD_TAG ?= $(shell sed 's/$(SED_MATCH)/-/g' <<< "$(CIRCLE_TAG)")
else
# Not in CircleCI environment, try to set sane defaults
BUILD_NUM = build-local
BRANCH_NAME ?= $(shell git rev-parse --abbrev-ref HEAD | sed 's/$(SED_MATCH)/-/g')
BUILD_TAG ?= $(shell git tag -l --points-at HEAD | tail -n1 | sed 's/$(SED_MATCH)/-/g')
endif

# If BUILD_TAG is blank there's no tag on this commit
ifeq ($(strip $(BUILD_TAG)),)
# Default to branch name
BUILD_TAG := $(BRANCH_NAME)
else
# Consider this the new :latest image
# FIXME: implement build tests before tagging with :latest
PUSH_LATEST := true
endif

REVISION_TAG = $(shell git rev-parse --short HEAD)

lint:
	yamllint .circleci/config.yml
	yamllint values.yaml
	yamllint env/dev/values.yaml
	yamllint env/prod/values.yaml

pull:
	docker pull gcr.io/planet-4-151612/openresty:latest

build: lint pull
	docker build \
		--tag=gcr.io/planet-4-151612/landing:$(BUILD_TAG) \
		--tag=gcr.io/planet-4-151612/landing:$(BUILD_NUM) \
		--tag=gcr.io/planet-4-151612/landing:$(REVISION_TAG) \
		.

push: push-tag push-latest

push-tag:
	docker push gcr.io/planet-4-151612/landing:$(BUILD_TAG)
	docker push gcr.io/planet-4-151612/landing:$(BUILD_NUM)

push-latest:
	@if [[ "$(PUSH_LATEST)" = "true" ]]; then { \
		docker tag gcr.io/planet-4-151612/landing:$(REVISION_TAG) gcr.io/planet-4-151612/landing:latest; \
		docker push gcr.io/planet-4-151612/landing:latest; \
	}	else { \
		echo "Not tagged.. skipping latest"; \
	} fi

dev: lint
	gcloud config set project $(DEV_PROJECT)
	gcloud container clusters get-credentials $(DEV_CLUSTER) --zone $(DEV_ZONE) --project $(DEV_PROJECT)
	helm init --client-only
	helm repo update
	helm upgrade --install --force --wait $(RELEASE_NAME) p4/static \
	  --version=$(CHART_VERSION) \
		--namespace=$(NAMESPACE) \
		--values values.yaml \
		--values env/dev/values.yaml

prod: lint
	gcloud config set project $(PROD_PROJECT)
	gcloud container clusters get-credentials $(PROD_CLUSTER) --zone $(PROD_ZONE) --project $(PROD_PROJECT)
	helm init --client-only
	helm repo update
	helm upgrade --install --force --wait $(RELEASE_NAME) p4/static \
		--version=$(CHART_VERSION) \
		--namespace=$(NAMESPACE) \
		--values values.yaml \
		--values env/prod/values.yaml

SHELL := /bin/bash
.DEFAULT_GOAL := help

AWS_PROFILE ?= default
AWS_REGION ?=
CLUSTERS_DIR ?= ./clusters

export AWS_PROFILE
export AWS_REGION
export CLUSTERS_DIR

.PHONY: help setup install-ssm-plugin doctor login deploy \
	tiup-deploy tiup-scale-out tiup-scale-in tiup-display tiup-start tiup-stop \
	tiup-reload tiup-prune tiup-upgrade tiup-destroy tiup-grafana \
	shell grafana prometheus dashboard mysql-tunnel

help:
	@echo "Available targets:"
	@echo "  make setup          Install and verify local dependencies (macOS only)"
	@echo "  make login          Log in to AWS SSO"
	@echo "  make tiup-deploy CLUSTER=name"
	@echo "                      Deploy/start clusters/name/topology.yaml"
	@echo "  make tiup-scale-out CLUSTER=name CHANGE=change"
	@echo "                      Apply clusters/name/scale-out/change.yaml"
	@echo "  make tiup-scale-in CLUSTER=name CHANGE=change"
	@echo "                      Apply clusters/name/scale-in/change.env"
	@echo "  make tiup-display CLUSTER=name"
	@echo "                      Display the selected TiUP cluster"
	@echo "  make tiup-{start,stop,reload,prune,upgrade,destroy} CLUSTER=name"
	@echo "                      Operate on the selected TiUP cluster"
	@echo "  make tiup-grafana CLUSTER=name"
	@echo "                      Forward Grafana from the selected topology"
	@echo "  make shell          Open a shell on the center instance through SSM"
	@echo "  make grafana        Forward localhost:3000 to Grafana"
	@echo "  make prometheus     Forward localhost:9090 to Prometheus"
	@echo "  make dashboard      Forward localhost:12379 to TiDB Dashboard"
	@echo "  make mysql-tunnel   Forward localhost:4000 to TiDB through HAProxy"

setup: install-ssm-plugin doctor

install-ssm-plugin:
	@bash ./scripts/install-ssm-plugin.sh

doctor:
	@command -v aws >/dev/null || (echo "AWS CLI v2 is not installed" >&2; exit 1)
	@command -v terraform >/dev/null || (echo "Terraform is not installed" >&2; exit 1)
	@command -v session-manager-plugin >/dev/null || (echo "AWS Session Manager plugin is not installed" >&2; exit 1)
	@aws --version
	@terraform version | head -1
	@session-manager-plugin --version

login:
	@aws sso login --profile "$(AWS_PROFILE)"

deploy: tiup-deploy

tiup-deploy tiup-display tiup-start tiup-stop tiup-reload tiup-prune tiup-upgrade tiup-destroy tiup-grafana:
	@test -n "$(CLUSTER)" || (echo "CLUSTER is required, for example: make $@ CLUSTER=cdc-test" >&2; exit 2)
	@action="$(@:tiup-%=%)"; bash ./scripts/tiup-cluster.sh "$$action" "$(CLUSTER)"

tiup-scale-out tiup-scale-in:
	@test -n "$(CLUSTER)" || (echo "CLUSTER is required, for example: make $@ CLUSTER=cdc-test CHANGE=my-change" >&2; exit 2)
	@test -n "$(CHANGE)" || (echo "CHANGE is required, for example: make $@ CLUSTER=$(CLUSTER) CHANGE=my-change" >&2; exit 2)
	@action="$(@:tiup-%=%)"; bash ./scripts/tiup-cluster.sh "$$action" "$(CLUSTER)" "$(CHANGE)"

shell grafana prometheus dashboard mysql-tunnel:
	@bash ./scripts/ssm-session.sh "$@"

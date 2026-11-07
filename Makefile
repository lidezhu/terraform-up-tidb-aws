SHELL := /bin/bash
.DEFAULT_GOAL := help

AWS_PROFILE ?= default
AWS_REGION ?=

export AWS_PROFILE
export AWS_REGION

.PHONY: help setup install-ssm-plugin doctor login shell grafana prometheus dashboard mysql-tunnel

help:
	@echo "Available targets:"
	@echo "  make setup          Install and verify local dependencies (macOS only)"
	@echo "  make login          Log in to AWS SSO"
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

shell grafana prometheus dashboard mysql-tunnel:
	@bash ./scripts/ssm-session.sh "$@"

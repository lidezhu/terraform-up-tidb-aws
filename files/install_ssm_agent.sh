#!/usr/bin/env bash
set -euxo pipefail

if systemctl list-unit-files --type=service | grep -q '^amazon-ssm-agent.service'; then
    systemctl enable --now amazon-ssm-agent.service
    exit 0
fi

if ! command -v snap >/dev/null 2>&1; then
    apt-get update
    apt-get install -y snapd
fi

if ! snap list amazon-ssm-agent >/dev/null 2>&1; then
    snap install amazon-ssm-agent --classic
fi

systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service

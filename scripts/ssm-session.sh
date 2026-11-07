#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: scripts/ssm-session.sh <shell|grafana|prometheus|dashboard|mysql-tunnel>
EOF
    exit 2
}

[[ $# -eq 1 ]] || usage

for command_name in aws terraform session-manager-plugin; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Required command is not installed: $command_name" >&2
        echo "Run 'make setup' on macOS, or install the dependencies manually." >&2
        exit 1
    fi
done

action="$1"
profile="${AWS_PROFILE:-default}"
region="${AWS_REGION:-}"

if [[ -z "$region" ]]; then
    region="$(terraform output -raw aws-region)"
fi

center_instance_id="${CENTER_INSTANCE_ID:-$(terraform output -raw center-instance-id)}"
monitoring_host="${MONITORING_HOST:-$(terraform output -raw pd-private-ip)}"

start_remote_forward() {
    local host="$1"
    local remote_port="$2"
    local local_port="$3"

    exec aws ssm start-session \
        --profile "$profile" \
        --region "$region" \
        --target "$center_instance_id" \
        --document-name AWS-StartPortForwardingSessionToRemoteHost \
        --parameters "{\"host\":[\"$host\"],\"portNumber\":[\"$remote_port\"],\"localPortNumber\":[\"$local_port\"]}"
}

case "$action" in
shell)
    exec aws ssm start-session \
        --profile "$profile" \
        --region "$region" \
        --target "$center_instance_id"
    ;;
grafana)
    echo "Grafana will be available at http://127.0.0.1:3000"
    start_remote_forward "$monitoring_host" 3000 3000
    ;;
prometheus)
    echo "Prometheus will be available at http://127.0.0.1:9090"
    start_remote_forward "$monitoring_host" 9090 9090
    ;;
dashboard)
    echo "TiDB Dashboard will be available at http://127.0.0.1:12379/dashboard"
    start_remote_forward "$monitoring_host" 2379 12379
    ;;
mysql-tunnel)
    echo "TiDB will be available at 127.0.0.1:4000"
    exec aws ssm start-session \
        --profile "$profile" \
        --region "$region" \
        --target "$center_instance_id" \
        --document-name AWS-StartPortForwardingSession \
        --parameters '{"portNumber":["4000"],"localPortNumber":["4000"]}'
    ;;
*)
    usage
    ;;
esac

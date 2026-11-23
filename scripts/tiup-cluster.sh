#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  scripts/tiup-cluster.sh deploy    <cluster>
  scripts/tiup-cluster.sh scale-out <cluster> <change>
  scripts/tiup-cluster.sh scale-in  <cluster> <change>
  scripts/tiup-cluster.sh display   <cluster>
  scripts/tiup-cluster.sh start     <cluster>
  scripts/tiup-cluster.sh stop      <cluster>
  scripts/tiup-cluster.sh reload    <cluster>
  scripts/tiup-cluster.sh prune     <cluster>
  scripts/tiup-cluster.sh upgrade   <cluster>
  scripts/tiup-cluster.sh destroy   <cluster>
  scripts/tiup-cluster.sh grafana   <cluster>

Clusters are loaded from ./clusters by default. Override with CLUSTERS_DIR.
EOF
    exit 2
}

[[ $# -ge 2 && $# -le 3 ]] || usage

action="$1"
cluster_selector="$2"
change_selector="${3:-}"

case "$action" in
deploy | display | start | stop | reload | prune | upgrade | destroy | grafana)
    [[ -z "$change_selector" ]] || usage
    ;;
scale-out | scale-in)
    [[ -n "$change_selector" ]] || usage
    ;;
*)
    usage
    ;;
esac

validate_selector() {
    local kind="$1"
    local value="$2"

    if [[ ! "$value" =~ ^[A-Za-z0-9._-]+$ ]] || [[ "$value" == "." || "$value" == ".." ]]; then
        echo "Invalid $kind: $value" >&2
        exit 2
    fi
}

read_config_value() {
    local key="$1"
    local file="$2"
    local value

    value="$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$file" | tail -1)"
    value="${value%$'\r'}"

    if [[ ${#value} -ge 2 && "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
        value="${value:1:${#value}-2}"
    elif [[ ${#value} -ge 2 && "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
        value="${value:1:${#value}-2}"
    fi

    printf '%s' "$value"
}

resolve_yaml_change() {
    local directory="$1"
    local selector="$2"
    local candidate

    case "$selector" in
    *.yaml | *.yml)
        candidate="$directory/$selector"
        ;;
    *)
        candidate="$directory/$selector.yaml"
        if [[ ! -f "$candidate" && -f "$directory/$selector.yml" ]]; then
            candidate="$directory/$selector.yml"
        fi
        ;;
    esac

    printf '%s' "$candidate"
}

validate_selector "cluster name" "$cluster_selector"
if [[ -n "$change_selector" ]]; then
    validate_selector "change name" "$change_selector"
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
clusters_directory="${CLUSTERS_DIR:-$repository_root/clusters}"
cluster_directory="$clusters_directory/$cluster_selector"
cluster_config="$cluster_directory/cluster.env"
topology_file="$cluster_directory/topology.yaml"

if [[ ! -d "$cluster_directory" ]]; then
    echo "Cluster directory not found: $cluster_directory" >&2
    exit 1
fi

if [[ ! -f "$cluster_config" ]]; then
    echo "Cluster config not found: $cluster_config" >&2
    exit 1
fi

cluster_name="$(read_config_value CLUSTER_NAME "$cluster_config")"
tidb_version="$(read_config_value TIDB_VERSION "$cluster_config")"

validate_selector "CLUSTER_NAME" "$cluster_name"
if [[ -n "$tidb_version" ]]; then
    validate_selector "TIDB_VERSION" "$tidb_version"
fi

local_operation_file=""
scale_in_nodes=""

case "$action" in
deploy | grafana)
    if [[ ! -f "$topology_file" ]]; then
        echo "Topology not found: $topology_file" >&2
        exit 1
    fi
    if [[ "$action" == "deploy" && -z "$tidb_version" ]]; then
        echo "TIDB_VERSION is required in $cluster_config for $action" >&2
        exit 1
    fi
    ;;
scale-out)
    local_operation_file="$(resolve_yaml_change "$cluster_directory/scale-out" "$change_selector")"
    if [[ ! -f "$local_operation_file" ]]; then
        echo "Scale-out topology not found: $local_operation_file" >&2
        exit 1
    fi
    ;;
scale-in)
    change_selector="${change_selector%.env}"
    local_operation_file="$cluster_directory/scale-in/$change_selector.env"
    if [[ ! -f "$local_operation_file" ]]; then
        echo "Scale-in config not found: $local_operation_file" >&2
        exit 1
    fi
    scale_in_nodes="$(read_config_value NODES "$local_operation_file")"
    if [[ -z "$scale_in_nodes" || ! "$scale_in_nodes" =~ ^[A-Za-z0-9.:_-]+(,[A-Za-z0-9.:_-]+)*$ ]]; then
        echo "NODES in $local_operation_file must be a comma-separated list of TiUP node IDs" >&2
        exit 1
    fi
    ;;
upgrade)
    if [[ -z "$tidb_version" ]]; then
        echo "TIDB_VERSION is required in $cluster_config for $action" >&2
        exit 1
    fi
    ;;
esac

if [[ "$action" == "grafana" ]]; then
    grafana_host="$(awk '
        /^grafana_servers:[[:space:]]*$/ { in_grafana = 1; next }
        in_grafana && /^[^[:space:]]/ { exit }
        in_grafana && $1 == "-" && $2 == "host:" { print $3; exit }
    ' "$topology_file")"
    grafana_host="${grafana_host%\"}"
    grafana_host="${grafana_host#\"}"
    grafana_host="${grafana_host%\'}"
    grafana_host="${grafana_host#\'}"

    if [[ -z "$grafana_host" || ! "$grafana_host" =~ ^[A-Za-z0-9.:_-]+$ ]]; then
        echo "Could not read grafana_servers[0].host from $topology_file" >&2
        exit 1
    fi

    MONITORING_HOST="$grafana_host" exec bash "$script_directory/ssm-session.sh" grafana
fi

for command_name in aws terraform session-manager-plugin ssh scp nc lsof; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Required command is not installed: $command_name" >&2
        echo "Run 'make setup' on macOS, or install the dependencies manually." >&2
        exit 1
    fi
done

profile="${AWS_PROFILE:-default}"
region="${AWS_REGION:-}"
ssh_port="${SSM_SSH_PORT:-2222}"
master_ssh_key="${MASTER_SSH_KEY:-./master_key}"

if [[ -z "$region" ]]; then
    region="$(terraform output -raw aws-region)"
fi

center_instance_id="${CENTER_INSTANCE_ID:-$(terraform output -raw center-instance-id)}"

if [[ ! -f "$master_ssh_key" ]]; then
    echo "SSH private key not found: $master_ssh_key" >&2
    exit 1
fi

if [[ ! "$ssh_port" =~ ^[0-9]+$ ]] || ((ssh_port < 1 || ssh_port > 65535)); then
    echo "SSM_SSH_PORT must be a valid TCP port" >&2
    exit 1
fi

temporary_directory="$(mktemp -d)"
tunnel_log="$temporary_directory/ssm-tunnel.log"
tunnel_pid=""
tunnel_listener_pid=""

cleanup() {
    if [[ -n "$tunnel_listener_pid" ]] && kill -0 "$tunnel_listener_pid" >/dev/null 2>&1; then
        kill "$tunnel_listener_pid" >/dev/null 2>&1 || true
    fi
    if [[ -n "$tunnel_pid" ]] && kill -0 "$tunnel_pid" >/dev/null 2>&1; then
        kill "$tunnel_pid" >/dev/null 2>&1 || true
        wait "$tunnel_pid" >/dev/null 2>&1 || true
    fi
    rm -rf "$temporary_directory"
}
trap cleanup EXIT INT TERM

echo "Waiting for the center instance to become available through SSM..."
ping_status=""
for _ in $(seq 1 120); do
    ping_status="$(aws ssm describe-instance-information \
        --profile "$profile" \
        --region "$region" \
        --filters "Key=InstanceIds,Values=$center_instance_id" \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text 2>/dev/null || true)"

    if [[ "$ping_status" == "Online" ]]; then
        break
    fi
    sleep 5
done

if [[ "$ping_status" != "Online" ]]; then
    echo "Center instance did not become available through SSM" >&2
    exit 1
fi

if nc -z 127.0.0.1 "$ssh_port" >/dev/null 2>&1; then
    echo "Local port $ssh_port is already in use; set SSM_SSH_PORT to another port" >&2
    exit 1
fi

aws ssm start-session \
    --profile "$profile" \
    --region "$region" \
    --target "$center_instance_id" \
    --document-name AWS-StartPortForwardingSession \
    --parameters "{\"portNumber\":[\"22\"],\"localPortNumber\":[\"$ssh_port\"]}" \
    >"$tunnel_log" 2>&1 &
tunnel_pid=$!

for _ in $(seq 1 60); do
    if nc -z 127.0.0.1 "$ssh_port" >/dev/null 2>&1; then
        break
    fi
    if ! kill -0 "$tunnel_pid" >/dev/null 2>&1; then
        cat "$tunnel_log" >&2
        exit 1
    fi
    sleep 1
done

if ! nc -z 127.0.0.1 "$ssh_port" >/dev/null 2>&1; then
    cat "$tunnel_log" >&2
    echo "Timed out while opening the SSM SSH tunnel" >&2
    exit 1
fi

tunnel_listener_pid="$(lsof -t -iTCP:"$ssh_port" -sTCP:LISTEN | head -1)"
if [[ -z "$tunnel_listener_pid" ]]; then
    echo "Could not identify the Session Manager tunnel process on port $ssh_port" >&2
    exit 1
fi

ssh_options=(
    -p "$ssh_port"
    -i "$master_ssh_key"
    -o "UserKnownHostsFile=$temporary_directory/known_hosts"
    -o StrictHostKeyChecking=accept-new
)
scp_options=(
    -P "$ssh_port"
    -i "$master_ssh_key"
    -o "UserKnownHostsFile=$temporary_directory/known_hosts"
    -o StrictHostKeyChecking=accept-new
)

echo "Waiting for center cloud-init to finish..."
ssh "${ssh_options[@]}" ubuntu@127.0.0.1 sudo cloud-init status --wait

remote_cluster_directory="/home/ubuntu/tiup-clusters/$cluster_selector"
remote_operation_file=""
remote_key_file="/tmp/tidb-master-key-$cluster_selector"

ssh "${ssh_options[@]}" ubuntu@127.0.0.1 mkdir -p "$remote_cluster_directory"
scp "${scp_options[@]}" "$cluster_config" ubuntu@127.0.0.1:"$remote_cluster_directory/cluster.env"

case "$action" in
deploy)
    remote_operation_file="$remote_cluster_directory/topology.yaml"
    scp "${scp_options[@]}" "$topology_file" ubuntu@127.0.0.1:"$remote_operation_file"
    ;;
scale-out)
    remote_operation_file="$remote_cluster_directory/scale-out-$change_selector.yaml"
    scp "${scp_options[@]}" "$local_operation_file" ubuntu@127.0.0.1:"$remote_operation_file"
    ;;
esac

scp "${scp_options[@]}" "$master_ssh_key" ubuntu@127.0.0.1:"$remote_key_file"
ssh "${ssh_options[@]}" ubuntu@127.0.0.1 \
    "install -m 0600 '$remote_key_file' /home/ubuntu/.ssh/id_rsa && rm -f '$remote_key_file'"

remote_operation_argument="${remote_operation_file:-__NONE__}"
scale_in_nodes_argument="${scale_in_nodes:-__NONE__}"

ssh "${ssh_options[@]}" ubuntu@127.0.0.1 bash -s -- \
    "$action" \
    "$cluster_name" \
    "$tidb_version" \
    "$remote_operation_argument" \
    "$scale_in_nodes_argument" <<'REMOTE_SCRIPT'
set -euo pipefail

action="$1"
cluster_name="$2"
tidb_version="$3"
operation_file="${4:-}"
scale_in_nodes="${5:-}"

if [[ "$operation_file" == "__NONE__" ]]; then
    operation_file=""
fi
if [[ "$scale_in_nodes" == "__NONE__" ]]; then
    scale_in_nodes=""
fi

identity_file=/home/ubuntu/.ssh/id_rsa
tiup=/home/ubuntu/.tiup/bin/tiup

if [[ ! -x "$tiup" ]]; then
    echo "TiUP is not installed on the center instance: $tiup" >&2
    exit 1
fi

wait_for_hosts() {
    local topology="$1"
    local host

    while read -r host; do
        echo "Waiting for cloud-init on $host..."
        ssh \
            -i "$identity_file" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            "ubuntu@$host" \
            sudo cloud-init status --wait
    done < <(awk '/^[[:space:]]*-[[:space:]]+host:/ {print $3}' "$topology" | sort -u)
}

"$tiup" install cluster

case "$action" in
deploy)
    wait_for_hosts "$operation_file"
    if "$tiup" cluster display "$cluster_name" >/dev/null 2>&1; then
        echo "TiDB cluster $cluster_name already exists; skipping deploy."
    else
        "$tiup" cluster deploy \
            "$cluster_name" \
            "$tidb_version" \
            "$operation_file" \
            --user ubuntu \
            -i "$identity_file" \
            --yes
    fi
    "$tiup" cluster start "$cluster_name" --yes
    ;;
scale-out)
    wait_for_hosts "$operation_file"
    "$tiup" cluster check \
        "$cluster_name" \
        "$operation_file" \
        --cluster \
        --user ubuntu \
        -i "$identity_file"
    "$tiup" cluster scale-out \
        "$cluster_name" \
        "$operation_file" \
        --user ubuntu \
        -i "$identity_file" \
        --yes
    ;;
scale-in)
    "$tiup" cluster scale-in "$cluster_name" --node "$scale_in_nodes" --yes
    ;;
display)
    "$tiup" cluster display "$cluster_name"
    ;;
start)
    "$tiup" cluster start "$cluster_name" --yes
    ;;
stop)
    "$tiup" cluster stop "$cluster_name" --yes
    ;;
reload)
    "$tiup" cluster reload "$cluster_name" --yes
    ;;
prune)
    "$tiup" cluster prune "$cluster_name" --yes
    ;;
upgrade)
    "$tiup" cluster upgrade "$cluster_name" "$tidb_version" --yes
    ;;
destroy)
    "$tiup" cluster destroy "$cluster_name" --yes
    ;;
*)
    echo "Unsupported remote action: $action" >&2
    exit 2
    ;;
esac
REMOTE_SCRIPT

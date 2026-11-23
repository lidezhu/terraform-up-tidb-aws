#!/usr/bin/env bash
set -euo pipefail

for command_name in mysql pgrep; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Required command is not installed: $command_name" >&2
        exit 1
    fi
done

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_port="${MYSQL_LOCAL_PORT:-4000}"

if [[ ! "$local_port" =~ ^[0-9]+$ ]] || ((local_port < 1 || local_port > 65535)); then
    echo "MYSQL_LOCAL_PORT must be a valid TCP port" >&2
    exit 2
fi

port_is_open() {
    (exec 3<>"/dev/tcp/127.0.0.1/$local_port") >/dev/null 2>&1
}

if port_is_open; then
    echo "Local port $local_port is already in use; set MYSQL_LOCAL_PORT to another port" >&2
    exit 1
fi

temporary_directory="$(mktemp -d)"
tunnel_log="$temporary_directory/mysql-tunnel.log"
tunnel_pid=""

terminate_process_tree() {
    local process_pid="$1"
    local child_pid

    while read -r child_pid; do
        [[ -n "$child_pid" ]] && terminate_process_tree "$child_pid"
    done < <(pgrep -P "$process_pid" 2>/dev/null || true)
    kill "$process_pid" >/dev/null 2>&1 || true
}

cleanup() {
    if [[ -n "$tunnel_pid" ]] && kill -0 "$tunnel_pid" >/dev/null 2>&1; then
        terminate_process_tree "$tunnel_pid"
        wait "$tunnel_pid" >/dev/null 2>&1 || true
    fi
    rm -rf "$temporary_directory"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

bash "$script_directory/ssm-session.sh" mysql-tunnel >"$tunnel_log" 2>&1 &
tunnel_pid=$!

for _ in $(seq 1 30); do
    if port_is_open; then
        break
    fi
    if ! kill -0 "$tunnel_pid" >/dev/null 2>&1; then
        cat "$tunnel_log" >&2
        exit 1
    fi
    sleep 1
done

if ! port_is_open; then
    cat "$tunnel_log" >&2
    echo "Timed out while opening the MySQL tunnel on local port $local_port" >&2
    exit 1
fi

mysql -u root --host 127.0.0.1 --port "$local_port"

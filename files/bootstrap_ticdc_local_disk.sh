#!/usr/bin/env bash

set -euo pipefail

mount_point=/mnt/ticdc
device=$(lsblk -dpno NAME,MODEL | awk '/Amazon EC2 NVMe Instance Storage/ { print $1; exit }')

if [[ -z "${device}" ]]; then
  echo "No EC2 NVMe instance store device found" >&2
  exit 1
fi

if ! sudo blkid "${device}" >/dev/null 2>&1; then
  sudo mkfs.ext4 -F "${device}"
fi

uuid=$(sudo blkid -s UUID -o value "${device}")
sudo mkdir -p "${mount_point}"

if ! grep -q "^UUID=${uuid}[[:space:]]" /etc/fstab; then
  echo "UUID=${uuid} ${mount_point} ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab >/dev/null
fi

if ! mountpoint -q "${mount_point}"; then
  sudo mount "${mount_point}"
fi

# TiUP creates the tidb user later during deployment.
sudo chmod 0777 "${mount_point}"

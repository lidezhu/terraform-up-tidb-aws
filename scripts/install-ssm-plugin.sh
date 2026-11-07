#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    cat >&2 <<'EOF'
This repository only automates local setup on macOS.

For other operating systems, install and configure these dependencies manually:

  1. AWS CLI v2
  2. Terraform
  3. AWS Session Manager plugin
  4. An AWS CLI profile with access to the target AWS account

Verify that these commands are available in PATH:

  aws --version
  terraform version
  session-manager-plugin --version

Then authenticate and verify AWS access:

  aws sso login --profile <profile>
  aws sts get-caller-identity --profile <profile>

Finally, run:

  make doctor AWS_PROFILE=<profile>

AWS Session Manager plugin documentation:
https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
EOF
    exit 1
fi

if command -v session-manager-plugin >/dev/null 2>&1; then
    echo "AWS Session Manager plugin is already installed:"
    session-manager-plugin --version
    exit 0
fi

case "$(uname -m)" in
arm64)
    package_path="mac_arm64"
    ;;
x86_64)
    package_path="mac"
    ;;
*)
    echo "Unsupported Mac architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

task_tmp_dir="$(mktemp -d)"
trap 'rm -rf "$task_tmp_dir"' EXIT

package="$task_tmp_dir/session-manager-plugin.pkg"
package_url="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/${package_path}/session-manager-plugin.pkg"

echo "Downloading AWS Session Manager plugin..."
curl --fail --location --silent --show-error "$package_url" -o "$package"

echo "Installing AWS Session Manager plugin..."
sudo installer -pkg "$package" -target /
sudo mkdir -p /usr/local/bin
sudo ln -sf \
    /usr/local/sessionmanagerplugin/bin/session-manager-plugin \
    /usr/local/bin/session-manager-plugin

echo "AWS Session Manager plugin installed successfully:"
session-manager-plugin --version

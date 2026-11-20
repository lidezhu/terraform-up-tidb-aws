# terraform-up-tidb-aws

A sample to create VMs for deploying TiDB in AWS using [Terraform](https://www.terraform.io) with these default topology:

| Usage                                       | Size   | Count | Private IP                  |
| ------------------------------------------- | ------ | ----- | --------------------------- |
| TiKV                                        | 8c 64g | 3     | 172.31.6.1, 172.31.6.2, ... |
| TiDB                                        | 8c 16g | 2     | 172.31.7.1, 172.31.7.2, ... |
| PD + Grafana + Monitoring                   | 8c 16g | 1     | 172.31.8.1                  |
| TiFlash                                     | 8c 64g | 0     | 172.31.9.1, 172.31.9.2, ... |
| Center VM, you can run benchmarks and so on | 8c 16g | 1     | 172.31.1.1                  |

The topology and instance size can be customized via [`locals_common.tf`](./locals_common.tf) and [`locals_advanced.tf`](./locals_advanced.tf).

## Prerequisite

- [Terraform](https://www.terraform.io) must be installed.

- `~/.ssh/id_rsa.pub` must present, can be used as the public key to access VMs.

- The AWS identity used locally must be allowed to start SSM sessions.

### Local setup and SSM access

Local dependency installation is automated on macOS (Intel and Apple Silicon):

```shell
make setup
make login
```

`make setup` installs the AWS Session Manager plugin when needed and verifies
AWS CLI, Terraform, and the plugin. Other operating systems are not installed
automatically; the command prints the dependencies and verification steps that
must be completed manually.

After `terraform apply`, use SSM to access the center node and cluster services:

```shell
make shell          # interactive shell on center
make grafana        # http://127.0.0.1:3000
make prometheus     # http://127.0.0.1:9090
make dashboard      # http://127.0.0.1:12379/dashboard
make mysql-tunnel   # MySQL on 127.0.0.1:4000
```

For a named TiUP cluster, use its configuration under `clusters/`:

```shell
make tiup-display CLUSTER=cdc-test
make tiup-grafana CLUSTER=cdc-test  # http://127.0.0.1:3000
```

All EC2 instances have private IP addresses only. Session Manager is used for
interactive access and port forwarding; no inbound connection from the
internet is required.

Override the default profile or region when needed:

```shell
make login AWS_PROFILE=my-profile
make grafana AWS_PROFILE=my-profile AWS_REGION=us-west-2
```

## Getting Started

### 1. Clone and create project

```shell
git clone https://github.com/breeswish/terraform-up-tidb-aws
cd terraform-up-tidb-aws

# Generate a master key for intra cluter access (no password)
ssh-keygen -t rsa -b 4096 -f ./master_key -q -N ""

# Load terraform modules
terraform init
```

### 2. Optional: Configure

Customize the number of TiDB and TiKV VMs in [`locals_common.tf`](./locals_common.tf).

**Example:**

```terraform
locals {
  name      = "foo-benchmark"
  n_tidb    = 1  # default 2
  n_tikv    = 3  # default 3
  n_tiflash = 0  # default 0
}
```

### 3. Create VMs

```shell
terraform apply -auto-approve
```

Terraform will output like this, which contains information you need to connect to VMs:

```plain
private-ip-pd = [
  "172.31.8.1",
]
private-ip-tidb = [
  "172.31.7.1",
  "172.31.7.2",
]
private-ip-tiflash = []
private-ip-tikv = [
  "172.31.6.1",
  "172.31.6.2",
  "172.31.6.3",
]
ssh-center = "make shell"
url-grafana = "Run 'make grafana', then open http://127.0.0.1:3000"
```

The private subnet uses a NAT gateway for outbound package and TiUP downloads.
The NAT gateway has an Elastic IP, but none of the EC2 instances has a public
IP address.

### 4. Deploy the cluster

Each TiUP cluster has its own directory:

```text
clusters/<name>/
├── cluster.env
├── topology.yaml
├── scale-out/
└── scale-in/
```

`cluster.env` contains the TiUP cluster name and version. Hosts, monitoring,
and Grafana remain in `topology.yaml`.

Deploy the `cdc-test` topology through a temporary SSM SSH tunnel:

```shell
make tiup-deploy CLUSTER=cdc-test
```

This waits for cloud-init on all nodes, uploads `master_key` to the center over
the temporary tunnel, deploys `clusters/cdc-test/topology.yaml`, and starts the
cluster.

To scale out, put a TiUP scale-out topology at
`clusters/cdc-test/scale-out/add-tikv-17.yaml`, then run:

```shell
make tiup-scale-out CLUSTER=cdc-test CHANGE=add-tikv-17
```

To scale in, create `clusters/cdc-test/scale-in/remove-tikv-17.env`:

```shell
NODES=172.31.6.17:20160
```

Then run:

```shell
make tiup-scale-in CLUSTER=cdc-test CHANGE=remove-tikv-17
make tiup-display CLUSTER=cdc-test
make tiup-prune CLUSTER=cdc-test
```

Other supported operations are `tiup-start`, `tiup-stop`, `tiup-reload`,
`tiup-upgrade`, and `tiup-destroy`. Set `CLUSTERS_DIR` only when cluster
directories are stored somewhere other than `./clusters`.

### 5. Connect to TiDB

A HAProxy is deployed in the Center VM, load balancing multiple TiDB instances.
Use SSM for a shell or local port forwarding:

```shell
make shell
make mysql-tunnel
# In another terminal:
mysql -u root --host 127.0.0.1 --port 4000
```

### 6. Finally, destroy VMs

When everything is done, you can destroy all of your VMs and resources with one line:

```shell
terraform destroy -auto-approve
```

## Features

| Status | Feature                                    |
| ------ | ------------------------------------------ |
| ✅     | Ubuntu 20.04 (x86_64)                      |
| ✅     | Intra-host public key authentication       |
| ✅     | HAProxy for multiple TiDB instances        |
| ✅     | Access PD and Grafana through SSM tunnels  |
| ✅     | EC2 instances use private IP addresses only |
| ✅     | Customize instance count and size          |
| ✅     | Enable core dump                           |
| ✅     | With zsh                                   |
| ✅     | TiDB recommended kernal parameters         |
| ✅     | Support TiFlash                            |
| ✅     | Instance size is identical with TiDB Cloud |
| ✅     | EC2 IAM Profile to access S3 without AK, SK |

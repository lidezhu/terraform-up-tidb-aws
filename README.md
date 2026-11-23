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

### Local setup

Local dependency installation is automated on macOS (Intel and Apple Silicon):

```shell
make setup
```

`make setup` installs the AWS Session Manager plugin when needed and verifies
AWS CLI, Terraform, and the plugin. Other operating systems are not installed
automatically; the command prints the dependencies and verification steps that
must be completed manually. If the selected AWS profile uses IAM Identity
Center, log in with the AWS CLI directly:

```shell
aws sso login --profile my-profile
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

#### Access through SSM

Use Session Manager to access the Center instance and private cluster services:

```shell
make shell          # interactive shell on Center
make grafana        # http://127.0.0.1:3000
make prometheus     # http://127.0.0.1:9090
make dashboard      # http://127.0.0.1:12379/dashboard
make mysql          # open a MySQL client through SSM
make mysql-tunnel   # MySQL on 127.0.0.1:4000
```

All EC2 instances have private IP addresses only. Session Manager provides
interactive access and port forwarding without inbound internet access. Set a
non-default profile or region on individual commands when needed:

```shell
make grafana AWS_PROFILE=my-profile AWS_REGION=us-west-2
```

The private subnet uses a NAT gateway for outbound package and TiUP downloads.
The NAT gateway has an Elastic IP, but none of the EC2 instances has a public
IP address.

### 4. Operate TiUP manually

The repository does not execute TiUP commands through an SSM SSH tunnel. Log
in to the Center instance and switch to the `ubuntu` user before operating
TiUP:

```shell
make shell
sudo -iu ubuntu
```

Terraform installs TiUP and writes the generated topologies to
`/home/ubuntu/topology*.yaml`. Before deploying or scaling a cluster, make sure
`/home/ubuntu/.ssh/id_rsa` exists, has mode `0600`, and can log in to the target
nodes as `ubuntu`. Create any additional scale topology files directly on the
Center instance.

#### Deploy and inspect

On the Center instance, deploy and start the cluster:

```shell
tiup cluster deploy cdc-test v8.5.8 /home/ubuntu/topology.yaml \
  --user ubuntu -i /home/ubuntu/.ssh/id_rsa --yes
tiup cluster start cdc-test --yes
```

Display the current topology and component status:

```shell
tiup cluster display cdc-test
```

A standard TiUP deployment creates the TiDB `root` account with an empty
password. Starting an existing cluster does not change its database password.

#### Start and stop

```shell
tiup cluster stop cdc-test --yes
tiup cluster start cdc-test --yes
```

These commands stop or start the TiUP cluster only. They do not stop or start
the EC2 instances.

#### Scale out

To scale out, create `/home/ubuntu/add-tikv-17.yaml` on Center. For example:

```yaml
tikv_servers:
  - host: 172.31.6.17
```

After provisioning the new EC2 instances with Terraform, run:

```shell
tiup cluster check cdc-test /home/ubuntu/add-tikv-17.yaml --cluster \
  --user ubuntu -i /home/ubuntu/.ssh/id_rsa
tiup cluster scale-out cdc-test /home/ubuntu/add-tikv-17.yaml \
  --user ubuntu -i /home/ubuntu/.ssh/id_rsa --yes
```

#### Scale in and prune

Run the following commands on Center:

```shell
tiup cluster scale-in cdc-test --node 172.31.6.17:20160 --yes
tiup cluster display cdc-test
tiup cluster prune cdc-test --yes
```

The `--node` value is a TiUP node ID, not only a host address. Obtain IDs from
`tiup cluster display`; separate multiple IDs with commas. For stateful
components such as TiKV and TiFlash, wait until removed nodes reach the
`Tombstone` state before pruning or deleting their EC2 instances.

#### Change configuration and reload

TiUP stores the active cluster configuration on the Center instance. To edit
it interactively:

```shell
tiup cluster edit-config cdc-test
```

After saving the configuration, apply it with:

```shell
tiup cluster reload cdc-test --yes
```

Editing the local initial `topology.yaml` after deployment does not by itself
change an existing cluster.

#### Upgrade

Run the upgrade on Center with the target version:

```shell
tiup cluster upgrade cdc-test v8.5.8 --yes
```

#### Destroy a TiUP cluster

```shell
tiup cluster destroy cdc-test --yes
```

This is destructive: TiUP stops the cluster, removes deployed data from the
cluster nodes, and removes the cluster's TiUP management metadata from Center.
It does not destroy EC2 instances or other Terraform resources.

#### Manual command reference

| Command | Purpose |
| --- | --- |
| `tiup cluster display <name>` | Display topology and component status |
| `tiup cluster start <name> --yes` | Start all cluster components |
| `tiup cluster stop <name> --yes` | Stop all cluster components |
| `tiup cluster scale-out ...` | Add nodes using a scale-out topology |
| `tiup cluster scale-in ...` | Remove the specified TiUP node IDs |
| `tiup cluster prune <name> --yes` | Remove Tombstone nodes from TiUP metadata |
| `tiup cluster edit-config <name>` | Edit the active TiUP configuration |
| `tiup cluster reload <name> --yes` | Apply the active TiUP configuration |
| `tiup cluster upgrade ...` | Upgrade the cluster to a target version |
| `tiup cluster destroy <name> --yes` | Destroy the TiUP cluster, but keep EC2 resources |

### 5. Connect to TiDB

A HAProxy is deployed in the Center VM, load balancing multiple TiDB instances.
Use the following command by default. It opens the SSM tunnel, connects the
MySQL client as `root`, and closes the tunnel when the client exits:

```shell
make mysql
```

If you need to customize the MySQL command line, such as the user, password,
or database, run only the tunnel in one terminal and use your own command in
another terminal:

```shell
# Terminal 1
make mysql-tunnel

# Terminal 2
mysql -u my_user -p --database my_database --host 127.0.0.1 --port 4000
```

If the cluster was started normally and still has an empty root password, set
one after connecting:

```sql
ALTER USER 'root'@'%' IDENTIFIED BY 'replace-with-a-strong-password';
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

# TiUP cluster directories

Each direct child directory represents one independently operated TiUP cluster:

```text
clusters/<name>/
├── cluster.env
├── topology.yaml
├── scale-out/<change>.yaml
└── scale-in/<change>.env
```

`cluster.env` contains only values that are not part of a TiUP topology:

```shell
CLUSTER_NAME=example
TIDB_VERSION=v8.5.8
```

Deploy and inspect a cluster by directory name:

```shell
make tiup-deploy CLUSTER=example
make tiup-display CLUSTER=example
```

The standard deploy/start leaves the new TiDB `root` password empty.

For scale-out, add a native TiUP scale-out topology and refer to its basename:

```shell
make tiup-scale-out CLUSTER=example CHANGE=add-tikv-04
```

For scale-in, put the TiUP node IDs in an env file:

```shell
# clusters/example/scale-in/remove-tikv-04.env
NODES=172.31.6.4:20160
```

Then run:

```shell
make tiup-scale-in CLUSTER=example CHANGE=remove-tikv-04
```

The default root is `./clusters`. Set `CLUSTERS_DIR` to override it.

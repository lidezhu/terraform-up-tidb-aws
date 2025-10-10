locals {
  name      = "cdc-test"
  n_tidb    = 3
  n_tikv    = 15
  n_ticdc   = 12
  n_tiflash = 0

  n_tidb_downstream = 1
  n_tikv_downstream = 10
}

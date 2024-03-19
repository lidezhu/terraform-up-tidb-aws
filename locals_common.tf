locals {
  name      = "ldz-test"
  n_tidb    = 1
  n_tikv    = 4
  n_ticdc   = 1
  n_tiflash = 0

  n_tidb_downstream = 1
  n_tikv_downstream = 3
}

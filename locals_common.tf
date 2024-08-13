locals {
  name      = "ldz-test"
  n_tidb    = 3
  n_tikv    = 4
  n_ticdc   = 2
  n_tiflash = 1

  n_tidb_downstream = 1
  n_tikv_downstream = 3
}

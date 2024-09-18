# Changes to these locals are easy to break something. Ensure you know what you are doing (see each comment).

locals {
  # image is region-local. If you changed region, please also change image.
  region = "us-east-2"
  image  = "ami-0fb653ca2d3203ac1" # Ubuntu 20.04

  # If you want to change instance type, ensure that GP3 EBS is available in the instance type.
  tidb_instance    = "c5.4xlarge"
  tikv_instance    = "r5.2xlarge"
  pd_instance      = "c5.4xlarge"
  tiflash_instance = "c5.9xlarge"
  ticdc_instance   = "c5.12xlarge"
  center_instance  = "c5.2xlarge"

  # TODO: deploy a load balancer for downstream
  tidb_downstream_instance    = "c5a.16xlarge"

  master_ssh_key         = "./master_key"
  master_ssh_public      = "./master_key.pub"
  alternative_ssh_public = "~/.ssh/id_rsa.pub"
}

# Changes to these locals are easy to break something. Ensure you know what you are doing (see each comment).

locals {
  # image is region-local. If you changed region, please also change image.
  region = "us-east-1"
  image  = "ami-0ecb62995f68bb549"  # Ubuntu 24.04

  # If you want to change instance type, ensure that GP3 EBS is available in the instance type.
  tidb_instance    = "c5.4xlarge"
  tikv_instance    = "r5b.2xlarge"
  pd_instance      = "c5.4xlarge"
  tiflash_instance = "c5.9xlarge"
  ticdc_instance   = "c6in.4xlarge"
  ticdc_local_instance = "i4i.2xlarge" # 8 vCPU, 64 GiB memory, one 1,875 GB local NVMe SSD
  center_instance  = "c5.2xlarge"

  # Leave empty to auto-select the first AZ that supports all required instance types.
  preferred_availability_zone = ""

  # TODO: deploy a load balancer for downstream
  tidb_downstream_instance    = "c5.9xlarge"

  master_ssh_key         = "./master_key"
  master_ssh_public      = "./master_key.pub"
  alternative_ssh_public = "~/.ssh/id_rsa.pub"
}

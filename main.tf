terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = local.region
  default_tags {
    tags = {
      Usage = local.name
    }
  }
}

data "aws_ssm_parameter" "ubuntu_2404_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_key_pair" "master_key" {
  public_key = file(local.master_ssh_public)
}

locals {
  tidb_private_ips            = [for index in range(local.n_tidb) : "172.31.7.${index + 1}"]
  tikv_private_ips            = [for index in range(local.n_tikv) : "172.31.6.${index + 1}"]
  tidb_downstream_private_ips = [for index in range(local.n_tidb_downstream) : "172.31.17.${index + 1}"]
  tikv_downstream_private_ips = [for index in range(local.n_tikv_downstream) : "172.31.16.${index + 1}"]
  tiflash_private_ips         = [for index in range(local.n_tiflash) : "172.31.9.${index + 1}"]
  ticdc_private_ips           = [for index in range(local.n_ticdc) : "172.31.10.${index + 1}"]
  ticdc_local_private_ips     = [for index in range(local.n_ticdc_local) : "172.31.11.${index + 1}"]

  common_cloud_init_vars = {
    install_ssm_agent_base64          = base64encode(file("${path.module}/files/install_ssm_agent.sh"))
    bootstrap_all_base64              = base64encode(file("${path.module}/files/bootstrap_all.sh"))
    alternative_ssh_public_base64     = base64encode(file(local.alternative_ssh_public))
    bootstrap_ticdc_local_disk_base64 = ""
    bootstrap_center_base64           = ""
    haproxy_config_base64             = ""
    topology_base64                   = ""
    topology_local_base64             = ""
    topology_downstream_base64        = ""
    topology_small_downstream_base64  = ""
  }

  node_user_data = templatefile("${path.module}/files/cloud_init.sh.tftpl", local.common_cloud_init_vars)

  ticdc_local_user_data = templatefile("${path.module}/files/cloud_init.sh.tftpl", merge(local.common_cloud_init_vars, {
    bootstrap_ticdc_local_disk_base64 = base64encode(file("${path.module}/files/bootstrap_ticdc_local_disk.sh"))
  }))

  center_user_data = templatefile("${path.module}/files/cloud_init.sh.tftpl", merge(local.common_cloud_init_vars, {
    bootstrap_center_base64 = base64encode(file("${path.module}/files/bootstrap_center.sh"))
    haproxy_config_base64 = base64encode(templatefile("${path.module}/files/haproxy.cfg.tftpl", {
      tidb_hosts = local.tidb_private_ips
    }))
    topology_base64 = base64encode(templatefile("${path.module}/files/topology.yaml.tftpl", {
      tidb_hosts    = local.tidb_private_ips
      tikv_hosts    = local.tikv_private_ips
      tiflash_hosts = local.tiflash_private_ips
      ticdc_hosts   = local.ticdc_private_ips
    }))
    topology_local_base64 = base64encode(templatefile("${path.module}/files/topology_local.yaml.tftpl", {
      tidb_hosts        = local.tidb_private_ips
      tikv_hosts        = local.tikv_private_ips
      tiflash_hosts     = local.tiflash_private_ips
      ticdc_local_hosts = local.ticdc_local_private_ips
    }))
    topology_downstream_base64 = base64encode(templatefile("${path.module}/files/topology-downstream.yaml.tftpl", {
      tidb_hosts = local.tidb_downstream_private_ips
      tikv_hosts = local.tikv_downstream_private_ips
    }))
    topology_small_downstream_base64 = base64encode(file("${path.module}/files/topology-small-downstream.yaml"))
  }))
}

resource "aws_instance" "tidb" {
  count = local.n_tidb

  depends_on = [
    aws_route_table_association.main,
    aws_iam_role_policy_attachment.ssm_managed_instance_core,
  ]

  ami                         = local.image
  instance_type               = local.tidb_instance
  key_name                    = aws_key_pair.master_key.id
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  subnet_id                   = aws_subnet.main.id
  associate_public_ip_address = false
  private_ip                  = local.tidb_private_ips[count.index]
  user_data                   = local.node_user_data

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size           = 500
    delete_on_termination = true
    volume_type           = "gp3"
    iops                  = 4000
    throughput            = 288
  }

  tags = {
    Name = "${local.name}-tidb-${count.index}"
  }

}

resource "aws_network_interface" "pd" {
  subnet_id       = aws_subnet.main.id
  private_ips     = ["172.31.8.1"]
  security_groups = [aws_security_group.ssh.id, aws_security_group.etcd.id, aws_security_group.grafana.id]
}

resource "aws_instance" "pd" {
  depends_on = [
    aws_route_table_association.main,
    aws_iam_role_policy_attachment.ssm_managed_instance_core,
  ]

  ami                  = local.image
  instance_type        = local.pd_instance
  key_name             = aws_key_pair.master_key.id
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  user_data            = local.node_user_data

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  network_interface {
    network_interface_id = aws_network_interface.pd.id
    device_index         = 0
  }

  root_block_device {
    volume_size           = 800
    delete_on_termination = true
    volume_type           = "gp3"
    iops                  = 4000
    throughput            = 288
  }

  tags = {
    Name = "${local.name}-pd-1"
  }

}

resource "aws_instance" "tikv" {
  count = local.n_tikv

  depends_on = [
    aws_route_table_association.main,
    aws_iam_role_policy_attachment.ssm_managed_instance_core,
  ]

  ami                         = local.image
  instance_type               = local.tikv_instance
  key_name                    = aws_key_pair.master_key.id
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  subnet_id                   = aws_subnet.main.id
  associate_public_ip_address = false
  private_ip                  = local.tikv_private_ips[count.index]
  user_data                   = local.node_user_data

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size           = 1024
    delete_on_termination = true
    volume_type           = "gp3"
    iops                  = 6000
    throughput            = 600
  }

  tags = {
    Name = "${local.name}-tikv-${count.index}"
  }

}

resource "aws_instance" "tidb-downstream" {
  count = local.n_tidb_downstream

  depends_on = [
    aws_route_table_association.main,
    aws_iam_role_policy_attachment.ssm_managed_instance_core,
  ]

  ami                         = local.image
  instance_type               = local.tidb_downstream_instance
  key_name                    = aws_key_pair.master_key.id
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  subnet_id                   = aws_subnet.main.id
  associate_public_ip_address = false
  private_ip                  = local.tidb_downstream_private_ips[count.index]
  user_data                   = local.node_user_data

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size           = 100
    delete_on_termination = true
    volume_type           = "gp3"
    iops                  = 4000
    throughput            = 288
  }

  tags = {
    Name = "${local.name}-tidb-downstream-${count.index}"
  }

}

resource "aws_instance" "tikv-downstream" {
  count = local.n_tikv_downstream

  depends_on = [
    aws_route_table_association.main,
    aws_iam_role_policy_attachment.ssm_managed_instance_core,
  ]

  ami                         = local.image
  instance_type               = local.tikv_instance
  key_name                    = aws_key_pair.master_key.id
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  subnet_id                   = aws_subnet.main.id
  associate_public_ip_address = false
  private_ip                  = local.tikv_downstream_private_ips[count.index]
  user_data                   = local.node_user_data

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size           = 500
    delete_on_termination = true
    volume_type           = "gp3"
    iops                  = 6000
    throughput            = 600
  }

  tags = {
    Name = "${local.name}-tikv-downstream-${count.index}"
  }

}

resource "aws_instance" "tiflash" {
  count = local.n_tiflash

  depends_on = [
    aws_route_table_association.main,
    aws_iam_role_policy_attachment.ssm_managed_instance_core,
  ]

  ami                         = local.image
  instance_type               = local.tiflash_instance
  key_name                    = aws_key_pair.master_key.id
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  subnet_id                   = aws_subnet.main.id
  associate_public_ip_address = false
  private_ip                  = local.tiflash_private_ips[count.index]
  user_data                   = local.node_user_data

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size           = 200
    delete_on_termination = true
    volume_type           = "gp3"
    iops                  = 12000
    throughput            = 288
  }

  tags = {
    Name = "${local.name}-tiflash-${count.index}"
  }

}

resource "aws_instance" "ticdc" {
  count = local.n_ticdc

  depends_on = [
    aws_route_table_association.main,
    aws_iam_role_policy_attachment.ssm_managed_instance_core,
  ]

  ami                         = local.image
  instance_type               = local.ticdc_instance
  key_name                    = aws_key_pair.master_key.id
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  subnet_id                   = aws_subnet.main.id
  associate_public_ip_address = false
  private_ip                  = local.ticdc_private_ips[count.index]
  user_data                   = local.node_user_data

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size           = 1024
    delete_on_termination = true
    volume_type           = "gp3"
    iops                  = 6000
    throughput            = 1000
  }

  tags = {
    Name = "${local.name}-ticdc-${count.index}"
  }

}

resource "aws_instance" "ticdc_local" {
  count = local.n_ticdc_local

  depends_on = [
    aws_route_table_association.main,
    aws_iam_role_policy_attachment.ssm_managed_instance_core,
  ]

  ami                         = local.image
  instance_type               = local.ticdc_local_instance
  key_name                    = aws_key_pair.master_key.id
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  subnet_id                   = aws_subnet.main.id
  associate_public_ip_address = false
  private_ip                  = local.ticdc_local_private_ips[count.index]
  user_data                   = local.ticdc_local_user_data

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size           = 50
    delete_on_termination = true
    volume_type           = "gp3"
  }

  # The mapping is explicit so changes involving the instance store recreate the instance.
  ephemeral_block_device {
    device_name  = "/dev/sdb"
    virtual_name = "ephemeral0"
  }

  tags = {
    Name = "${local.name}-ticdc-local-${count.index}"
  }

}

resource "aws_network_interface" "center" {
  subnet_id       = aws_subnet.main.id
  private_ips     = ["172.31.1.1"]
  security_groups = [aws_security_group.ssh.id]
}

resource "aws_instance" "center" {
  depends_on = [
    aws_route_table_association.main,
    aws_iam_role_policy_attachment.ssm_managed_instance_core,
  ]

  ami                  = local.image
  instance_type        = local.center_instance
  key_name             = aws_key_pair.master_key.id
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  user_data            = local.center_user_data

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  network_interface {
    network_interface_id = aws_network_interface.center.id
    device_index         = 0
  }

  root_block_device {
    volume_size           = 200
    delete_on_termination = true
    volume_type           = "gp3"
    iops                  = 4000
    throughput            = 288
  }

  tags = {
    Name = "${local.name}-center"
  }
}

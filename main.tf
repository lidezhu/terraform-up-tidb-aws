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

resource "aws_key_pair" "master_key" {
  public_key = file(local.master_ssh_public)
}

locals {
  provisioner_add_alternative_ssh_public = [
    "echo '${file(local.alternative_ssh_public)}' | tee -a ~/.ssh/authorized_keys",
  ]
}

resource "aws_instance" "tidb" {
  count = local.n_tidb

  ami                         = local.image
  instance_type               = local.tidb_instance
  key_name                    = aws_key_pair.master_key.id
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  subnet_id                   = aws_subnet.main.id
  associate_public_ip_address = true
  private_ip                  = "172.31.7.${count.index + 1}"

  root_block_device {
    volume_size           = 100
    delete_on_termination = true
    volume_type           = "gp3"
    iops                  = 4000
    throughput            = 288
  }

  tags = {
    Name = "${local.name}-tidb-${count.index}"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(local.master_ssh_key)
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = local.provisioner_add_alternative_ssh_public
  }
  provisioner "remote-exec" {
    script = "./files/bootstrap_all.sh"
  }
}

resource "aws_network_interface" "pd" {
  subnet_id       = aws_subnet.main.id
  private_ips     = ["172.31.8.1"]
  security_groups = [aws_security_group.ssh.id, aws_security_group.etcd.id, aws_security_group.grafana.id]
}

resource "aws_instance" "pd" {
  ami                         = local.image
  instance_type               = local.pd_instance
  key_name                    = aws_key_pair.master_key.id
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name

  network_interface {
    network_interface_id = aws_network_interface.pd.id
    device_index         = 0
  }

  root_block_device {
    volume_size           = 500
    delete_on_termination = true
    volume_type           = "gp3"
    iops                  = 4000
    throughput            = 288
  }

  tags = {
    Name = "${local.name}-pd-1"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(local.master_ssh_key)
    host        = aws_eip.pd.public_ip
  }

  provisioner "remote-exec" {
    inline = local.provisioner_add_alternative_ssh_public
  }
  provisioner "remote-exec" {
    script = "./files/bootstrap_all.sh"
  }
}

resource "aws_instance" "tikv" {
  count = local.n_tikv

  ami                         = local.image
  instance_type               = local.tikv_instance
  key_name                    = aws_key_pair.master_key.id
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  subnet_id                   = aws_subnet.main.id
  associate_public_ip_address = true
  private_ip                  = "172.31.6.${count.index + 1}"

  root_block_device {
    volume_size           = 500
    delete_on_termination = true
    volume_type           = "gp3"
    iops                  = 6000
    throughput            = 600
  }

  tags = {
    Name = "${local.name}-tikv-${count.index}"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(local.master_ssh_key)
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = local.provisioner_add_alternative_ssh_public
  }
  provisioner "remote-exec" {
    script = "./files/bootstrap_all.sh"
  }
}

resource "aws_instance" "tidb-downstream" {
  count = local.n_tidb_downstream

  ami                         = local.image
  instance_type               = local.tidb_downstream_instance
  key_name                    = aws_key_pair.master_key.id
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  subnet_id                   = aws_subnet.main.id
  associate_public_ip_address = true
  private_ip                  = "172.31.17.${count.index + 1}"

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

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(local.master_ssh_key)
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = local.provisioner_add_alternative_ssh_public
  }
  provisioner "remote-exec" {
    script = "./files/bootstrap_all.sh"
  }
}

resource "aws_instance" "tikv-downstream" {
  count = local.n_tikv_downstream

  ami                         = local.image
  instance_type               = local.tikv_instance
  key_name                    = aws_key_pair.master_key.id
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  subnet_id                   = aws_subnet.main.id
  associate_public_ip_address = true
  private_ip                  = "172.31.16.${count.index + 1}"

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

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(local.master_ssh_key)
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = local.provisioner_add_alternative_ssh_public
  }
  provisioner "remote-exec" {
    script = "./files/bootstrap_all.sh"
  }
}

resource "aws_instance" "tiflash" {
  count = local.n_tiflash

  ami                         = local.image
  instance_type               = local.tiflash_instance
  key_name                    = aws_key_pair.master_key.id
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  subnet_id                   = aws_subnet.main.id
  associate_public_ip_address = true
  private_ip                  = "172.31.9.${count.index + 1}"

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

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(local.master_ssh_key)
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = local.provisioner_add_alternative_ssh_public
  }
  provisioner "remote-exec" {
    script = "./files/bootstrap_all.sh"
  }
}

resource "aws_instance" "ticdc" {
  count = local.n_ticdc

  ami                         = local.image
  instance_type               = local.ticdc_instance
  key_name                    = aws_key_pair.master_key.id
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  subnet_id                   = aws_subnet.main.id
  associate_public_ip_address = true
  private_ip                  = "172.31.10.${count.index + 1}"

  root_block_device {
    volume_size           = 2048
    delete_on_termination = true
    volume_type           = "gp3"
    iops                  = 6000
    throughput            = 1000
  }

  tags = {
    Name = "${local.name}-ticdc-${count.index}"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(local.master_ssh_key)
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = local.provisioner_add_alternative_ssh_public
  }
  provisioner "remote-exec" {
    script = "./files/bootstrap_all.sh"
  }
}

resource "aws_network_interface" "center" {
  subnet_id       = aws_subnet.main.id
  private_ips     = ["172.31.1.1"]
  security_groups = [aws_security_group.ssh.id]
}

resource "aws_instance" "center" {
  ami                         = local.image
  instance_type               = local.center_instance
  key_name                    = aws_key_pair.master_key.id
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name

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

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(local.master_ssh_key)
    host        = aws_eip.center.public_ip
  }

  provisioner "file" {
    content = templatefile("./files/haproxy.cfg.tftpl", {
      tidb_hosts = aws_instance.tidb.*.private_ip,
    })
    destination = "/home/ubuntu/haproxy.cfg"
  }

  provisioner "file" {
    content = templatefile("./files/topology.yaml.tftpl", {
      tidb_hosts = aws_instance.tidb.*.private_ip,
      tikv_hosts = aws_instance.tikv.*.private_ip,
      tiflash_hosts = aws_instance.tiflash.*.private_ip,
      ticdc_hosts = aws_instance.ticdc.*.private_ip,
    })
    destination = "/home/ubuntu/topology.yaml"
  }

  provisioner "file" {
    content = templatefile("./files/topology-downstream.yaml.tftpl", {
      tidb_hosts = aws_instance.tidb-downstream.*.private_ip,
      tikv_hosts = aws_instance.tikv-downstream.*.private_ip,
    })
    destination = "/home/ubuntu/topology-downstream.yaml"
  }

  provisioner "remote-exec" {
    inline = local.provisioner_add_alternative_ssh_public
  }
  provisioner "remote-exec" {
    script = "./files/bootstrap_all.sh"
  }

  # add keys to access other hosts
  provisioner "file" {
    source      = local.master_ssh_key
    destination = "/home/ubuntu/.ssh/id_rsa"
  }
  provisioner "file" {
    source      = local.master_ssh_public
    destination = "/home/ubuntu/.ssh/id_rsa.pub"
  }
  provisioner "remote-exec" {
    inline = [
      "chmod 400 ~/.ssh/id_rsa",
    ]
  }

  provisioner "remote-exec" {
    script = "./files/bootstrap_center.sh"
  }
}

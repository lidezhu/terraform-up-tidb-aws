data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ec2_instance_type_offerings" "required" {
  for_each = local.required_instance_types

  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [each.value]
  }
}

locals {
  required_instance_types = toset(compact([
    local.n_tidb > 0 ? local.tidb_instance : "",
    local.n_tikv > 0 ? local.tikv_instance : "",
    local.pd_instance,
    local.n_tiflash > 0 ? local.tiflash_instance : "",
    local.n_ticdc > 0 ? local.ticdc_instance : "",
    local.n_ticdc_local > 0 ? local.ticdc_local_instance : "",
    local.center_instance,
    local.n_tidb_downstream > 0 ? local.tidb_downstream_instance : "",
    local.n_tikv_downstream > 0 ? local.tikv_instance : "",
  ]))

  supported_azs_by_instance_type = {
    for instance_type, offering in data.aws_ec2_instance_type_offerings.required :
    instance_type => toset(offering.locations)
  }

  common_availability_zones = [
    for az in data.aws_availability_zones.available.names : az
    if length([
      for instance_type in local.required_instance_types : instance_type
      if contains(local.supported_azs_by_instance_type[instance_type], az)
    ]) == length(local.required_instance_types)
  ]

  selected_availability_zone = contains(local.common_availability_zones, local.preferred_availability_zone) ? local.preferred_availability_zone : local.common_availability_zones[0]
}

resource "aws_vpc" "main" {
  cidr_block = "172.31.0.0/16"
}

resource "aws_subnet" "main" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.31.0.0/16"
  availability_zone = local.selected_availability_zone
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

resource "aws_eip" "center" {
  vpc                       = true
  depends_on                = [aws_internet_gateway.main]
  network_interface         = aws_network_interface.center.id
  associate_with_private_ip = "172.31.1.1"
}

resource "aws_eip" "pd" {
  vpc                       = true
  depends_on                = [aws_internet_gateway.main]
  network_interface         = aws_network_interface.pd.id
  associate_with_private_ip = "172.31.8.1"
}

resource "aws_security_group" "ssh" {
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }
  vpc_id = aws_vpc.main.id
}

resource "aws_security_group" "etcd" {
  ingress {
    from_port   = 2379
    to_port     = 2379
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  vpc_id = aws_vpc.main.id
}

resource "aws_security_group" "grafana" {
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  vpc_id = aws_vpc.main.id
}

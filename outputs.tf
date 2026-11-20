output "ssh-center" {
  value = "make shell"
}

output "aws-region" {
  value = local.region
}

output "center-instance-id" {
  value = aws_instance.center.id
}

output "cluster-name" {
  value = local.name
}

output "pd-private-ip" {
  value = aws_instance.pd.private_ip
}

output "url-tidb-dashboard" {
  value = "Run 'make dashboard', then open http://127.0.0.1:12379/dashboard"
}

output "url-grafana" {
  value = "Run 'make grafana', then open http://127.0.0.1:3000"
}

output "private-ip-tidb" {
  value = aws_instance.tidb.*.private_ip
}

output "private-ip-tikv" {
  value = aws_instance.tikv.*.private_ip
}

output "private-ip-tiflash" {
  value = aws_instance.tiflash.*.private_ip
}

output "private-ip-ticdc" {
  value = aws_instance.ticdc.*.private_ip
}

output "private-ip-ticdc-local" {
  value = aws_instance.ticdc_local.*.private_ip
}

output "private-ip-pd" {
  value = aws_instance.pd.*.private_ip
}

output "private-ip-tidb-downstream" {
  value = aws_instance.tidb-downstream.*.private_ip
}

output "private-ip-tikv-downstream" {
  value = aws_instance.tikv-downstream.*.private_ip
}

output "common-availability-zones" {
  value = local.common_availability_zones
}

output "selected-availability-zone" {
  value = local.selected_availability_zone
}

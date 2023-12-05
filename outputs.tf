output "ssh-center" {
  value = "ssh ubuntu@${aws_instance.center.public_ip}"
}

output "url-tidb-dashboard" {
  value = "http://${aws_instance.pd.public_ip}:2379/dashboard"
}

output "url-grafana" {
  value = "http://${aws_instance.pd.public_ip}:3000"
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

output "private-ip-pd" {
  value = aws_instance.pd.*.private_ip
}

output "url-tidb-downstream-dashboard" {
  value = "http://${aws_instance.pd-downstream.public_ip}:2379/dashboard"
}

output "url-downstream-grafana" {
  value = "http://${aws_instance.pd-downstream.public_ip}:3000"
}

output "private-ip-tidb-downstream" {
  value = aws_instance.tidb-downstream.*.private_ip
}

output "private-ip-tikv-downstream" {
  value = aws_instance.tikv-downstream.*.private_ip
}

output "private-ip-pd-downstream" {
  value = aws_instance.pd-downstream.*.private_ip
}

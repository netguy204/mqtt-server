output "fqdn" {
  description = "The broker's fully-qualified domain name."
  value       = local.fqdn
}

output "public_ip" {
  description = "Elastic IP address of the broker."
  value       = aws_eip.broker.public_ip
}

output "route53_nameservers" {
  description = "Nameservers for the Route53 subdomain zone. Add these as NS records at your registrar (Squarespace) for the broker's FQDN to delegate the subdomain to Route53."
  value       = aws_route53_zone.mqtt.name_servers
}

output "ssm_connect_command" {
  description = "Open a shell on the broker via SSM Session Manager (no SSH)."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.broker.id}"
}

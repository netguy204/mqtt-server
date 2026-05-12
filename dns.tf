locals {
  fqdn = "${var.hostname}.${var.parent_domain}"
}

# Route53 zone for the subdomain only. Delegate to this zone by adding NS
# records at Squarespace for `<hostname>.<parent_domain>` pointing at the
# four nameservers in the `route53_nameservers` output.
resource "aws_route53_zone" "mqtt" {
  name    = local.fqdn
  comment = "MQTT broker subdomain — delegated from ${var.parent_domain}"
}

resource "aws_route53_record" "mqtt_a" {
  zone_id = aws_route53_zone.mqtt.zone_id
  name    = local.fqdn
  type    = "A"
  ttl     = 60
  records = [aws_eip.broker.public_ip]
}

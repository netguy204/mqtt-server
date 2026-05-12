variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "parent_domain" {
  description = "Apex domain hosted at your registrar (Squarespace). E.g. \"example.com\". Terraform creates a Route53 hosted zone for the subdomain (see `hostname`); you must add NS records for that subdomain at Squarespace, pointing at the Route53 nameservers (see outputs)."
  type        = string
}

variable "hostname" {
  description = "Subdomain prefix for the broker. The broker's FQDN is `<hostname>.<parent_domain>`."
  type        = string
  default     = "mqtt"
}

variable "letsencrypt_email" {
  description = "Email address used for Let's Encrypt account registration and expiration notices."
  type        = string
}

variable "mqtt_users" {
  description = "Map of MQTT username to plaintext password. Seeded into mosquitto's password file at first boot. Changes to this map require `terraform taint aws_instance.broker && terraform apply` (or destroy/recreate) to take effect."
  type        = map(string)
  sensitive   = true

  validation {
    condition     = length(var.mqtt_users) > 0
    error_message = "At least one MQTT user must be defined."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the broker."
  type        = string
  default     = "t3.micro"
}

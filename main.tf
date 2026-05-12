data "aws_availability_zones" "available" {
  state = "available"
}

# Filter AZs to those that actually offer the chosen instance type. Some AZs
# (often us-east-1a) don't offer newer/cheaper instance types in every account.
data "aws_ec2_instance_type_offerings" "broker" {
  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
  filter {
    name   = "location"
    values = data.aws_availability_zones.available.names
  }
  location_type = "availability-zone"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "mqtt-broker"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "mqtt-broker"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = tolist(data.aws_ec2_instance_type_offerings.broker.locations)[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "mqtt-broker-public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "mqtt-broker-public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "broker" {
  name        = "mqtt-broker"
  description = "MQTT broker: MQTTS 8883 + MQTT 1883 inbound, all egress."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MQTTS"
    from_port   = 8883
    to_port     = 8883
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description = "MQTT (plaintext)"
    from_port   = 1883
    to_port     = 1883
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_eip" "broker" {
  domain = "vpc"
  tags = {
    Name = "mqtt-broker"
  }
}

resource "aws_instance" "broker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  depends_on             = [aws_route_table_association.public]
  vpc_security_group_ids = [aws_security_group.broker.id]
  iam_instance_profile   = aws_iam_instance_profile.broker.name

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    fqdn              = local.fqdn
    letsencrypt_email = var.letsencrypt_email
    mqtt_users        = var.mqtt_users
    aws_region        = var.aws_region
  })

  # Re-run user_data when any of the inputs change (forces instance replace).
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = {
    Name = "mqtt-broker"
  }
}

resource "aws_eip_association" "broker" {
  instance_id   = aws_instance.broker.id
  allocation_id = aws_eip.broker.id
}

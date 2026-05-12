data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "broker" {
  name               = "mqtt-broker"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# SSM Session Manager access (no SSH).
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.broker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Route53 write access scoped to the mqtt subdomain zone, used by certbot's
# dns-route53 plugin to solve the DNS-01 challenge.
data "aws_iam_policy_document" "route53_certbot" {
  statement {
    actions   = ["route53:ListHostedZones", "route53:GetChange"]
    resources = ["*"]
  }
  statement {
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [aws_route53_zone.mqtt.arn]
  }
}

resource "aws_iam_role_policy" "route53_certbot" {
  name   = "route53-certbot"
  role   = aws_iam_role.broker.id
  policy = data.aws_iam_policy_document.route53_certbot.json
}

resource "aws_iam_instance_profile" "broker" {
  name = "mqtt-broker"
  role = aws_iam_role.broker.name
}

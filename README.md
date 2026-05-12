# mqtt-server

Terraform that defines a self-hosted [Mosquitto](https://mosquitto.org) MQTT
broker on a bare EC2 VM in AWS. TLS via Let's Encrypt (DNS-01 through Route53),
username/password auth, state in S3 so you can maintain it from any machine.

Designed to be destroyed and recreated on demand — the entire broker is one
`terraform apply` away from existing or not existing.

## What it builds

- VPC + public subnet + IGW + route table (10.0.0.0/16)
- Security group: inbound TCP 8883 (MQTTS) only
- t3.micro EC2 instance, Ubuntu 24.04, Elastic IP attached
- IAM role with SSM Session Manager + scoped Route53 write (for certbot)
- Route53 hosted zone for `<subdomain>.<parent_domain>`, delegated from your
  registrar
- Mosquitto with a Let's Encrypt cert, password file seeded from variables,
  cert auto-renewal via `certbot.timer` + deploy hook

Shell access is SSM-only (no SSH, no key pair, port 22 not open).

Cost: roughly $8/month on-demand (t3.micro + EIP + Route53 zone).

## Install

Installation is a prompt, not a todo list. Paste the following into Claude
Code (or another coding agent) from the repo root — it will gather your
inputs, run the deploy, and walk you through the one manual step (DNS
delegation at your registrar).

````
You're deploying this MQTT broker for me. The Terraform is already written;
your job is to collect inputs, run the deploy, and verify it works.

PREREQS — check and install if missing (macOS commands shown; adapt for Linux):
- Terraform >= 1.11    `brew install tfenv && tfenv install 1.11.4 && tfenv use 1.11.4`
- AWS CLI v2           `brew install awscli`
- SSM plugin           `brew install --cask session-manager-plugin`
- Mosquitto clients    `brew install mosquitto`   (for the smoke test at the end)

ASK ME (one message, all at once):
1. AWS region — default us-east-1
2. Parent domain registered at my registrar (e.g. example.com)
3. Subdomain prefix — default `mqtt` (so the broker lives at mqtt.example.com)
4. Let's Encrypt email (used for renewal notices)
5. MQTT usernames + passwords (one or more pairs, generate strong passwords if I don't supply them)
6. Globally-unique S3 bucket name for Terraform state
7. Where my AWS credentials live: `.env` file with AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY, or my default AWS profile

If credentials are in `.env`, run every terraform command with
`set -a; source .env; set +a` first.

DEPLOY:
1. `cd bootstrap && terraform init`
   `terraform apply -var aws_region=<region> -var state_bucket_name=<bucket>`
2. Write `../backend.hcl` with two raw lines (no heredoc, no extra keys):
       bucket = "<bucket>"
       region = "<region>"
3. Write `../terraform.tfvars` matching the structure of `terraform.tfvars.example`,
   filled with the values I gave you. Make sure it's gitignored (it is by default).
4. `cd .. && terraform init -backend-config=backend.hcl`
5. `terraform apply`

DNS DELEGATION (the one manual step):
6. Run `terraform output route53_nameservers` — you'll get four AWS nameservers.
7. Tell me to log into my registrar's DNS panel and create four NS records on
   the parent domain, host = the subdomain prefix, each pointing at one of the
   four nameservers. Do NOT create an A record — Route53 owns that.
8. Wait for me to confirm I've added them. Then poll:
       dig +short NS <fqdn> @8.8.8.8
   every 30s until it returns the four AWS nameservers. Give up after 10 minutes
   and ask me to recheck the registrar.

VERIFY THE BROKER:
9. Tail the bootstrap log via SSM. Don't use `aws ssm start-session` — it
   opens an interactive PTY your shell can't drive (it'll fail with "EOF").
   Use `send-command` + `get-command-invocation` instead:

       INSTANCE=$(terraform output -raw ssm_connect_command | awk '{print $NF}')
       CMD_ID=$(aws ssm send-command --instance-ids $INSTANCE \
           --document-name AWS-RunShellScript \
           --parameters 'commands=["sudo tail -n 200 /var/log/mqtt-bootstrap.log"]' \
           --query "Command.CommandId" --output text)
       sleep 3
       aws ssm get-command-invocation --command-id $CMD_ID --instance-id $INSTANCE \
           --query StandardOutputContent --output text

   Look for "Successfully received certificate" and the mosquitto enable line.
   If you see "certbot failed (likely waiting for NS delegation); retrying in
   60s...", that's expected — wait 60s and re-run send-command, don't
   intervene on the instance. Give up after ~10 attempts and ask me to recheck
   the NS records at the registrar.

10. Smoke-test the roundtrip:
        mosquitto_sub -h <fqdn> -p 8883 -u <user> -P <pass> -t 'test/#' -v &
        mosquitto_pub -h <fqdn> -p 8883 -u <user> -P <pass> -t 'test/hello' -m 'world'
    Confirm the subscriber prints the message. If TLS verification fails on
    macOS, add `--capath /etc/ssl/certs` to both commands.

COMMON FAILURE MODES — debug, don't bail:
- "no matching EC2 VPC found" → there's no default VPC; the config already
  creates its own, so this only fires if you didn't run `apply` yet.
- "instance type not supported in AZ" → the config filters AZs by offering;
  if you see this, the data source is probably broken — investigate.
- `backend.hcl` rejected → it should be two raw `key = "value"` lines, not
  the wrapped output of `terraform output`.
- Certbot loop never succeeds → DNS delegation is wrong; recheck NS records
  at the registrar with `dig +trace <fqdn>`.
- IAM permission denied → tell me which permission is missing and which
  AWS principal needs it.

When you're done, tell me the FQDN, the smoke-test result, and the
`ssm start-session` command for future shell access.
````

## Uninstall

```
Destroy everything this Terraform created. Run `terraform destroy` from the
repo root with credentials sourced. After it finishes, remind me to remove
the four NS records at my registrar (Terraform doesn't manage those) and
to optionally `cd bootstrap && terraform destroy` to remove the state bucket
itself if I'm done for good.
```

## Maintaining from another machine

State lives in the S3 bucket created by `bootstrap/`, so any machine with
the right AWS credentials and `backend.hcl` can take over:

```
git clone <this repo>
cd <repo>
# put your AWS creds in .env (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
# put bucket/region into backend.hcl
set -a; source .env; set +a
terraform init -backend-config=backend.hcl
terraform plan   # should show "no changes"
```

## Rotating MQTT passwords

Edit `terraform.tfvars`, then `terraform apply`. Because the password file is
seeded by cloud-init (run once per instance), changing `mqtt_users` triggers a
full instance replacement — the broker is unreachable for ~90 seconds during
the swap. The EIP, DNS, and Let's Encrypt account survive the replace.

## Files

| Path | Purpose |
| --- | --- |
| `versions.tf` | Provider + S3 backend (partial config) |
| `variables.tf` | Input variables |
| `main.tf` | VPC, subnet, IGW, route table, SG, EIP, EC2 |
| `dns.tf` | Route53 zone + A record |
| `iam.tf` | EC2 instance role (SSM + scoped Route53 write) |
| `outputs.tf` | FQDN, public IP, nameservers, SSM command |
| `user_data.sh.tftpl` | Cloud-init: installs mosquitto, gets cert, configures listener |
| `bootstrap/` | One-time: creates the S3 bucket that holds Terraform state |
| `terraform.tfvars.example` | Copy to `terraform.tfvars` and fill in |

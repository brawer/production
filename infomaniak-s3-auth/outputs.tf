# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# Consumed by ../infomaniak-storage via a local `terraform_remote_state`
# data source - see that module's main.tf for why not a direct reference.
# Same caveat as bunny/'s zone passwords: ends up in this module's
# terraform.tfstate in plaintext. It's gitignored - keep it private.
output "access" {
  description = "S3-compatible access key (EC2 credential 'access'). KEEP SECRET."
  value       = openstack_identity_ec2_credential_v3.s3.access
  sensitive   = true
}

output "secret" {
  description = "S3-compatible secret key (EC2 credential 'secret'). KEEP SECRET."
  value       = openstack_identity_ec2_credential_v3.s3.secret
  sensitive   = true
}

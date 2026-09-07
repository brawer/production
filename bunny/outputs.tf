# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# S3-compatible storage endpoint URL per zone.
output "s3_endpoints" {
  description = "Map of zone name => S3-compatible endpoint URL."
  value = {
    for name, zone in bunnynet_storage_zone.this :
    name => "https://${zone.hostname_s3}"
  }
}

# HTTP API endpoint URL per zone (bunnycdn Storage API).
output "api_endpoints" {
  description = "Map of zone name => HTTP Storage API endpoint URL."
  value = {
    for name, zone in bunnynet_storage_zone.this :
    name => "https://${zone.hostname}"
  }
}

# Bunny storage zone IDs, useful for cross-referencing in other configs.
output "storage_zone_ids" {
  description = "Map of zone name => Bunny storage zone ID."
  value = {
    for name, zone in bunnynet_storage_zone.this :
    name => zone.id
  }
}

# Read-write passwords - these are the S3 secret keys. KEEP SECRET.
output "passwords" {
  description = "Map of zone name => read-write password (S3 secret key)."
  value = {
    for name, zone in bunnynet_storage_zone.this :
    name => zone.password
  }
  sensitive = true
}

# Read-only passwords, for download-only clients. KEEP SECRET.
output "passwords_readonly" {
  description = "Map of zone name => read-only password."
  value = {
    for name, zone in bunnynet_storage_zone.this :
    name => zone.password_readonly
  }
  sensitive = true
}

# Full "access_key:secret_key" pairs for use with the AWS CLI or S3 clients.
# For Bunny S3, the access key ID is the zone name and the secret is `password`.
output "s3_credentials" {
  description = "Map of zone name => \"<zone-name>:<password>\"."
  value = {
    for name, zone in bunnynet_storage_zone.this :
    name => "${zone.name}:${zone.password}"
  }
  sensitive = true
}

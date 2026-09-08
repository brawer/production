# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# S3-compatible endpoint per zone. Bunny's S3 endpoint is per-region, so zones
# in the same region share a value; the zone name is the bucket / access key ID
# and the secret is the zone password (see s3_credentials). Path-style only.
output "s3_endpoints" {
  description = "Map of zone name => S3-compatible endpoint URL."
  value = {
    for name, zone in bunnynet_storage_zone.this :
    name => "https://${zone.hostname_s3}"
  }
}

# Base URL per zone for the native Bunny Storage HTTP API. Path-style: the zone
# name is part of the URL. Authenticate with header "AccessKey: <password>".
output "api_endpoints" {
  description = "Map of zone name => native Bunny Storage HTTP API base URL."
  value = {
    for name, zone in bunnynet_storage_zone.this :
    name => "https://${zone.hostname}/${zone.name}/"
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

# Nameservers to set at the registrar to move DNS to Bunny.
output "dns_nameservers" {
  description = "Nameservers to configure at the registrar for the managed domain."
  value       = [bunnynet_dns_zone.this.nameserver1, bunnynet_dns_zone.this.nameserver2]
}

# The *.b-cdn.net hostname of every pull zone, for testing before DNS is moved
# and for wiring the /data/* edge rules.
output "pullzone_cdn_domains" {
  description = "Map of site => Bunny *.b-cdn.net hostname(s)."
  value = merge(
    { for k, pz in bunnynet_pullzone.site : k => "${pz.name}.b-cdn.net" },
    { for k, pz in bunnynet_pullzone.data : "${k} (data)" => "${pz.name}.b-cdn.net" },
  )
}

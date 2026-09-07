# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# The storage zones to manage. The map key is the zone name, which is also the
# globally unique S3 bucket name.
#
#   region              - primary region code: BR, DE, JH, LA, NY, SE, SG, SYD, UK
#   zone_tier           - "Standard" (HDD, single region) or "Edge" (SSD, replicated)
#   replication_regions - optional geo-replication regions (extra cost)
locals {
  storage_zones = {
    "brawer-homepage" = {
      region              = "DE"
      zone_tier           = "Standard"
      replication_regions = []
    }
    "osmdiffs-data" = {
      region              = "DE"
      zone_tier           = "Standard"
      replication_regions = []
    }
    "osmdiffs-app" = {
      region              = "DE"
      zone_tier           = "Standard"
      replication_regions = []
    }
  }
}

# One S3-compatible storage zone per entry in local.storage_zones.
#
# Each zone exposes a computed `password` (read-write) and `password_readonly`.
# For S3-compatible access the zone name is the access key ID and `password`
# is the secret key. See outputs.tf.
resource "bunnynet_storage_zone" "this" {
  for_each = local.storage_zones

  name                = each.key
  region              = each.value.region
  zone_tier           = each.value.zone_tier
  replication_regions = each.value.replication_regions
}

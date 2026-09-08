# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# CDN layer: one Bunny pull zone per hostname group, each fronting a storage zone.
#
# dandelis.ch is the guinea pig for the brawer.ch migration - it mirrors the
# layout brawer.ch will eventually use. To add brawer.ch later, add entries here
# (and a DNS zone + records in dns.tf).
#
#   origin_zone - storage zone (key in local.storage_zones) serving the site root
#   hostnames   - every hostname attached to the pull zone; the first non-
#                 canonical one gets a 301 redirect to `canonical`
#   canonical   - the hostname all others redirect to, and the /data/* match host
#   data_zone   - optional storage zone that /data/* is routed to via an edge rule
locals {
  sites = {
    "dandelis-homepage" = {
      origin_zone = "brawer-homepage"
      hostnames   = ["dandelis.ch", "www.dandelis.ch"]
      canonical   = "dandelis.ch"
      data_zone   = null
    }
    "dandelis-osmviews" = {
      origin_zone = "osmviews-app"
      hostnames   = ["osmviews.dandelis.ch"]
      canonical   = "osmviews.dandelis.ch"
      data_zone   = "osmviews-data"
    }
    "dandelis-osmdiffs" = {
      origin_zone = "osmdiffs-app"
      hostnames   = ["osmdiffs.dandelis.ch"]
      canonical   = "osmdiffs.dandelis.ch"
      data_zone   = "osmdiffs-data"
    }
  }

  # Flattened (site, hostname) pairs, keyed "<site>|<hostname>". Used for pull
  # zone hostnames, DNS records, and the canonical-redirect edge rules.
  site_hostnames = merge([
    for site, cfg in local.sites : {
      for host in cfg.hostnames : "${site}|${host}" => {
        site      = site
        hostname  = host
        canonical = cfg.canonical
      }
    }
  ]...)

  # Sites that need a /data/* -> storage zone edge rule.
  data_sites = {
    for site, cfg in local.sites : site => cfg if cfg.data_zone != null
  }
}

# One pull zone per site, origin = its storage zone.
resource "bunnynet_pullzone" "site" {
  for_each = local.sites

  name = each.key

  origin {
    type        = "StorageZone"
    storagezone = bunnynet_storage_zone.this[each.value.origin_zone].id
  }

  routing {
    tier = "Standard"
  }
}

# Custom hostnames. Omitting certificate/certificate_key selects a managed
# Let's Encrypt certificate, which Bunny issues once the hostname resolves to
# the pull zone (i.e. after the registrar nameserver switch).
resource "bunnynet_pullzone_hostname" "site" {
  for_each = local.site_hostnames

  pullzone    = bunnynet_pullzone.site[each.value.site].id
  name        = each.value.hostname
  tls_enabled = true
  force_ssl   = true
}

# 301 every non-canonical hostname to the canonical one, preserving the path.
resource "bunnynet_pullzone_edgerule" "canonical_redirect" {
  for_each = {
    for key, sh in local.site_hostnames : key => sh
    if sh.hostname != sh.canonical
  }

  enabled     = true
  pullzone    = bunnynet_pullzone.site[each.value.site].id
  description = "Redirect ${each.value.hostname} to ${each.value.canonical}"

  actions = [
    {
      type       = "Redirect"
      parameter1 = "https://${each.value.canonical}{{path}}"
      parameter2 = "301"
      parameter3 = null
    }
  ]

  match_type = "MatchAny"
  triggers = [
    {
      type       = "Url"
      match_type = "MatchAny"
      patterns   = ["*://${each.value.hostname}/*"]
      parameter1 = null
      parameter2 = null
    }
  ]
}

# Route /data/* to a separate storage zone (the "data" bucket for the project).
# Bunny's Origin Storage Zone action preserves the request path, so an object
# requested as /data/x lands at key data/x in the target zone.
resource "bunnynet_pullzone_edgerule" "data_route" {
  for_each = local.data_sites

  enabled     = true
  pullzone    = bunnynet_pullzone.site[each.key].id
  description = "Route /data/* to storage zone ${each.value.data_zone}"

  actions = [
    {
      type       = "OriginStorage"
      parameter1 = tostring(bunnynet_storage_zone.this[each.value.data_zone].id)
      parameter2 = null
      parameter3 = null
    }
  ]

  match_type = "MatchAny"
  triggers = [
    {
      type       = "Url"
      match_type = "MatchAny"
      patterns   = ["*://${each.value.canonical}/data/*"]
      parameter1 = null
      parameter2 = null
    }
  ]
}

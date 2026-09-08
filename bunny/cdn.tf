# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# CDN layer: one Bunny pull zone per site, each fronting a storage zone.
#
# dandelis.ch is the guinea pig for the brawer.ch migration - it mirrors the
# layout brawer.ch will eventually use. Each site is keyed by its canonical
# hostname; the pull zone name is that hostname with dots turned to dashes
# (dandelis.ch -> dandelis-ch). Moving a domain to production is then a literal
# "dandelis" -> "brawer" substitution of a copied block - the origin storage
# zones are already domain-independent.
#
#   origin_zone - storage zone (key in local.storage_zones) serving the site root
#   aliases     - extra hostnames on the pull zone, each 301-redirected to the key
#   data_zone   - optional storage zone served at /data/* (via its own bare pull
#                 zone and an OriginUrl edge rule; see below)
locals {
  sites = {
    "dandelis.ch" = {
      origin_zone = "brawer-homepage"
      aliases     = ["www.dandelis.ch"]
      data_zone   = null
    }
    "osmviews.dandelis.ch" = {
      origin_zone = "osmviews-app"
      aliases     = []
      data_zone   = "osmviews-data-de"
    }
    "osmdiffs.dandelis.ch" = {
      origin_zone = "osmdiffs-app"
      aliases     = []
      data_zone   = "osmdiffs-data-de"
    }
  }

  # Pull zone name per site: canonical hostname with dots as dashes.
  pullzone_names = { for host in keys(local.sites) : host => replace(host, ".", "-") }

  # Flattened (site, hostname) pairs, keyed "<canonical>|<hostname>". Used for
  # pull zone hostnames, DNS records, and the canonical-redirect edge rules.
  site_hostnames = merge([
    for host, cfg in local.sites : {
      for h in concat([host], cfg.aliases) : "${host}|${h}" => {
        site      = host
        hostname  = h
        canonical = host
      }
    }
  ]...)

  # Sites that need a /data/* -> storage zone edge rule.
  data_sites = {
    for host, cfg in local.sites : host => cfg if cfg.data_zone != null
  }
}

# One pull zone per site, origin = its storage zone.
resource "bunnynet_pullzone" "site" {
  for_each = local.sites

  name = local.pullzone_names[each.key]

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

# 301 every alias hostname to the canonical one, preserving the path.
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

# A bare pull zone (b-cdn.net only, no custom hostname) fronting the project's
# data storage zone. It exists purely as the target of the /data/* edge rule
# below: Bunny's edge-rule "Origin Storage Zone" action (OriginStorage) is
# rejected with "Storage zone not valid" regardless of parameter form, so the
# supported path is an OriginUrl override to another pull zone's b-cdn.net host.
resource "bunnynet_pullzone" "data" {
  for_each = local.data_sites

  name = "${local.pullzone_names[each.key]}-data"

  origin {
    type        = "StorageZone"
    storagezone = bunnynet_storage_zone.this[each.value.data_zone].id
  }

  routing {
    tier = "Standard"
  }
}

# Route /data/* on the site to its data pull zone. Bunny appends the request
# path to the OriginUrl, so /data/x is fetched as <data-pz>.b-cdn.net/data/x
# and served from key data/x in the data storage zone.
resource "bunnynet_pullzone_edgerule" "data_route" {
  for_each = local.data_sites

  enabled     = true
  pullzone    = bunnynet_pullzone.site[each.key].id
  description = "Route /data/* to ${bunnynet_pullzone.data[each.key].name}"

  actions = [
    {
      type       = "OriginUrl"
      parameter1 = "https://${bunnynet_pullzone.data[each.key].name}.b-cdn.net"
      parameter2 = null
      parameter3 = null
    }
  ]

  match_type = "MatchAny"
  triggers = [
    {
      type       = "Url"
      match_type = "MatchAny"
      patterns   = ["*://${each.key}/data/*"]
      parameter1 = null
      parameter2 = null
    }
  ]
}

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
#   kind        - "hugo" (Hugo static site) or "spa" (client-routed React/Vite
#                 bundle). Selects the content-hashed URL globs for the immutable
#                 cache edge rule (local.immutable_globs), and - spa only, still a
#                 TODO below - a 404 -> /index.html history-fallback rule.
locals {
  sites = {
    "dandelis.ch" = {
      origin_zone = "brawer-homepage"
      aliases     = ["www.dandelis.ch"]
      data_zone   = null
      kind        = "hugo"
    }
    "osmviews.dandelis.ch" = {
      origin_zone = "osmviews-app"
      aliases     = []
      data_zone   = "osmviews-data-de"
      kind        = "spa"
    }
    "osmdiffs.dandelis.ch" = {
      origin_zone = "osmdiffs-app"
      aliases     = []
      data_zone   = "osmdiffs-data-de"
      kind        = "spa"
    }
  }

  # Edge + browser TTL (seconds) for content-hashed assets. A hashed URL is in
  # principle safe to pin forever (31536000 + an `immutable` token), but keep it
  # short until a real deploy has proven both that the globs below match only
  # hashed files and that the build actually fingerprints - a wrong glob pinning
  # HTML for a year is only recoverable with a purge. Bump (and add `immutable`
  # to the Cache-Control string) in a follow-up once verified on dandelis.ch.
  immutable_max_age = 600

  # Content-hashed asset URL globs per site kind. Files matching these carry a
  # hash in the path (Hugo `| fingerprint` output, Hugo image processing, Vite's
  # /assets/). Everything else rides the short pull zone default
  # (cache_expiration_time), which is what a deploy needs to bust HTML within
  # minutes without an edge purge.
  #
  # Bunny caps a single edge-rule trigger at 5 patterns, so immutable_assets
  # chunks these into groups of 5 (rule match_type MatchAny ORs the chunks). The
  # image list is only what this site's templates emit (picture.html -> webp +
  # avif); add extensions here if that changes.
  immutable_globs = {
    hugo = [
      "/*.min.*.css", "/*.min.*.js",
      "/*_hu*.webp", "/*_hu*.avif",
      "/fonts/*",
    ]
    spa = ["/assets/*"]
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

  # Bunny storage origins emit no Cache-Control, so without an explicit override
  # the edge TTL is undefined. Pin a short default: a deploy is then visible
  # within minutes with no purge (we keep the account API key out of CI on
  # purpose). Content-hashed assets get a longer TTL from immutable_assets below.
  # cache_stale serves the old copy instantly while the edge revalidates in the
  # background, and while the origin is unreachable.
  cache_expiration_time         = 300
  cache_expiration_time_browser = 300
  cache_stale                   = ["updating", "offline"]
  strip_cookies                 = true
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

# Content-hashed assets get a longer cache than the pull zone default. Their URL
# changes whenever their bytes change (the build puts a hash in the filename), so
# old and new copies coexist in the storage zone and the deploy pipeline never
# needs to purge (nor be handed the un-scopeable account API key). TTL is
# local.immutable_max_age - kept short until proven, see the comment there.
#
# OverrideCacheTime sets the edge TTL; SetResponseHeader sets what the browser
# sees. The match globs are per-site-kind (local.immutable_globs) and have to
# track what each build emits - see brawer/homepage#81 for the Hugo side.
resource "bunnynet_pullzone_edgerule" "immutable_assets" {
  for_each = local.sites

  enabled     = true
  pullzone    = bunnynet_pullzone.site[each.key].id
  description = "Longer cache for content-hashed assets"

  actions = [
    {
      type       = "OverrideCacheTime"
      parameter1 = tostring(local.immutable_max_age)
      parameter2 = null
      parameter3 = null
    },
    {
      type       = "SetResponseHeader"
      parameter1 = "Cache-Control"
      parameter2 = "public, max-age=${local.immutable_max_age}"
      parameter3 = null
    },
  ]

  # Bunny allows at most 5 patterns per trigger, so chunk the globs and OR the
  # chunks (match_type MatchAny).
  match_type = "MatchAny"
  triggers = [
    for chunk in chunklist([for g in local.immutable_globs[each.value.kind] : "*://${each.key}${g}"], 5) : {
      type       = "Url"
      match_type = "MatchAny"
      patterns   = chunk
      parameter1 = null
      parameter2 = null
    }
  ]
}

# TODO (when the first SPA frontend is built and deployable): kind == "spa" sites
# need a history-API fallback so client-routed paths (/osmviews/47.3/8.5) render
# index.html instead of a storage 404. Planned shape:
#
#   trigger  StatusCode == 404  AND  Url MatchNone "*://<host>/data/*"
#   action   OriginUrl -> "https://<pullzone>.b-cdn.net/index.html"
#
# Both the StatusCode trigger and the OriginUrl action exist in the provider.
# Unverified: whether Bunny appends the request path to that OriginUrl (the
# /data/* rule below relies on it doing exactly that) - test on dandelis.ch
# before relying on it; the fallbacks are a custom error page or an edge script.

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

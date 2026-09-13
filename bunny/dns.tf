# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

locals {
  dns_domain = "dandelis.ch"
}

# DNS for dandelis.ch, hosted on Bunny DNS. After `tofu apply`, point the
# dandelis.ch nameservers at the values in the `dns_nameservers` output at the
# registrar. dandelis.ch is a parked domain with no records to migrate; add any
# MX/TXT/etc. here before switching nameservers.
resource "bunnynet_dns_zone" "this" {
  domain = local.dns_domain
}

# One PullZone-type record per hostname, linked to the pull zone that serves it.
# Bunny resolves these to the CDN and provisions the managed TLS certificate.
resource "bunnynet_dns_record" "site" {
  for_each = local.site_hostnames

  zone = bunnynet_dns_zone.this.id
  name = each.value.hostname == local.dns_domain ? "" : trimsuffix(each.value.hostname, ".${local.dns_domain}")

  type        = "PullZone"
  value       = bunnynet_pullzone.site[each.value.site].name
  pullzone_id = bunnynet_pullzone.site[each.value.site].id
}

# Mail, hosted by Infomaniak.
resource "bunnynet_dns_record" "mx" {
  zone = bunnynet_dns_zone.this.id
  name = ""

  type     = "MX"
  value    = "mta-gw.infomaniak.ch"
  priority = 5
}

resource "bunnynet_dns_record" "spf" {
  zone = bunnynet_dns_zone.this.id
  name = ""

  type  = "TXT"
  value = "v=spf1 include:spf.infomaniak.ch -all"
}

resource "bunnynet_dns_record" "autoconfig" {
  zone = bunnynet_dns_zone.this.id
  name = "autoconfig"

  type  = "CNAME"
  value = "infomaniak.com"
}

resource "bunnynet_dns_record" "autodiscover" {
  zone = bunnynet_dns_zone.this.id
  name = "autodiscover"

  type  = "CNAME"
  value = "infomaniak.com"
}

resource "bunnynet_dns_record" "dkim" {
  zone = bunnynet_dns_zone.this.id
  name = "20260913._domainkey"

  type  = "TXT"
  value = "v=DKIM1; t=s; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAths3IJ4hH4vXmzj402ZrbLYSMhCJ4PBV7e9roPTRDIta/R7QxmOnLEA8h5phLl3sxQf7Vg4SiTuDZ0PTWpLeRnkIrPbx0sIfNfKvfFUbzVM65PbTMQWQNQ+bo/TJKq2FHZtgZr5/KVqilDj7gsGdEqYZTUZG/tX1nxAHQNNWjSS54fAFCkwAqMj2qckhOoKDf2bc8i1TBCST9jH62aqDk36PsIc7dlFfCHtsbDUS8bRo3dfR+mUdj7CGG5w4cFcHRblTBhl6mfSVSM6yu+eB0YnzBiK60SB97ISPESXFNcey8rMoaK3IZdiOVT+uIknE9jQyRjsVk6NpDR6zT41UPQIDAQAB"
}

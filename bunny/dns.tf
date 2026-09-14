# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

locals {
  # Domains with a Bunny-hosted DNS zone. Both registrar-transferred to
  # Infomaniak and NS-delegated to Bunny (issue #6, verified 2026-09-14). See
  # local.sites (cdn.tf) for each domain's cutover flag.
  dns_domains = ["dandelis.ch", "brawer.ch"]

  # Domains with Infomaniak-hosted mail: identical MX/SPF/autoconfig/
  # autodiscover records for each.
  mail_domains = ["dandelis.ch", "brawer.ch"]

  # Per-domain DKIM selector + Infomaniak-issued public key. A domain only
  # gets a DKIM record once it's been added in the Infomaniak mail admin and
  # the key is known - the other mail_domains records don't depend on this.
  mail_dkim = {
    "dandelis.ch" = {
      selector = "20260913"
      value    = "v=DKIM1; t=s; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAths3IJ4hH4vXmzj402ZrbLYSMhCJ4PBV7e9roPTRDIta/R7QxmOnLEA8h5phLl3sxQf7Vg4SiTuDZ0PTWpLeRnkIrPbx0sIfNfKvfFUbzVM65PbTMQWQNQ+bo/TJKq2FHZtgZr5/KVqilDj7gsGdEqYZTUZG/tX1nxAHQNNWjSS54fAFCkwAqMj2qckhOoKDf2bc8i1TBCST9jH62aqDk36PsIc7dlFfCHtsbDUS8bRo3dfR+mUdj7CGG5w4cFcHRblTBhl6mfSVSM6yu+eB0YnzBiK60SB97ISPESXFNcey8rMoaK3IZdiOVT+uIknE9jQyRjsVk6NpDR6zT41UPQIDAQAB"
    }
    "brawer.ch" = {
      selector = "20260913"
      value    = "v=DKIM1; t=s; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAv/0gP9aYtAw1K+HhO5B43qjC9pcQmcSqNtipuwWhVitwRKBQ5YM5qn1QlSe/iShXW0D7Iv/oMf8s251+JTtdR9Kr91IY99csHfeD/Ece/ZK5I/d5DU0BQej73XlhXcXFUfzHC4DDKodqV8wH1scP1oWYut6NurnWM1LrBch8jnrixaRp+u+ki6OJaEISw6uQVM6Q3pWWDdUtDnji6KRZzTRiB/AsuQypquTlGYesVWUo44EX1HJNreQaZAGiJf6/wKraVZWQBWWCiJhw9Br3aT9B+c50etQb8x2ex5D774x2T1NBBLN35dgMuY0Il0cbUUBrKoy9TLkNFl5tf6Xo9wIDAQAB"
    }
  }
}

# DNS for every domain in local.dns_domains, hosted on Bunny DNS. After
# `tofu apply`, point each domain's nameservers at the values in the
# `dns_nameservers` output at its registrar.
resource "bunnynet_dns_zone" "this" {
  for_each = toset(local.dns_domains)

  domain = each.value
}

moved {
  from = bunnynet_dns_zone.this
  to   = bunnynet_dns_zone.this["dandelis.ch"]
}

# One PullZone-type record per hostname, linked to the pull zone that serves it.
# Bunny resolves these to the CDN and provisions the managed TLS certificate.
resource "bunnynet_dns_record" "site" {
  for_each = local.site_hostnames

  zone = bunnynet_dns_zone.this[each.value.domain].id
  name = each.value.hostname == each.value.domain ? "" : trimsuffix(each.value.hostname, ".${each.value.domain}")

  type        = "PullZone"
  value       = bunnynet_pullzone.site[each.value.site].name
  pullzone_id = bunnynet_pullzone.site[each.value.site].id
}

# Mail, hosted by Infomaniak.
resource "bunnynet_dns_record" "mx" {
  for_each = toset(local.mail_domains)

  zone = bunnynet_dns_zone.this[each.value].id
  name = ""

  type     = "MX"
  value    = "mta-gw.infomaniak.ch"
  priority = 5
}

moved {
  from = bunnynet_dns_record.mx
  to   = bunnynet_dns_record.mx["dandelis.ch"]
}

resource "bunnynet_dns_record" "spf" {
  for_each = toset(local.mail_domains)

  zone = bunnynet_dns_zone.this[each.value].id
  name = ""

  type  = "TXT"
  value = "v=spf1 include:spf.infomaniak.ch -all"
}

moved {
  from = bunnynet_dns_record.spf
  to   = bunnynet_dns_record.spf["dandelis.ch"]
}

resource "bunnynet_dns_record" "autoconfig" {
  for_each = toset(local.mail_domains)

  zone = bunnynet_dns_zone.this[each.value].id
  name = "autoconfig"

  type  = "CNAME"
  value = "infomaniak.com"
}

moved {
  from = bunnynet_dns_record.autoconfig
  to   = bunnynet_dns_record.autoconfig["dandelis.ch"]
}

resource "bunnynet_dns_record" "autodiscover" {
  for_each = toset(local.mail_domains)

  zone = bunnynet_dns_zone.this[each.value].id
  name = "autodiscover"

  type  = "CNAME"
  value = "infomaniak.com"
}

moved {
  from = bunnynet_dns_record.autodiscover
  to   = bunnynet_dns_record.autodiscover["dandelis.ch"]
}

resource "bunnynet_dns_record" "dkim" {
  for_each = local.mail_dkim

  zone = bunnynet_dns_zone.this[each.key].id
  name = "${each.value.selector}._domainkey"

  type  = "TXT"
  value = each.value.value
}

moved {
  from = bunnynet_dns_record.dkim
  to   = bunnynet_dns_record.dkim["dandelis.ch"]
}

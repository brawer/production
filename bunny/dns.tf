# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

locals {
  # Domains with a Bunny-hosted DNS zone. dandelis.ch was decommissioned
  # (issue #6 follow-up, 2026-09-14): it was only ever a guinea pig for the
  # brawer.ch migration, now parked with Infomaniak (no Bunny-hosted DNS, no
  # website, no mail) now that brawer.ch is the real live domain.
  dns_domains = ["brawer.ch"]

  # Domains with Infomaniak-hosted mail: identical MX/SPF/autoconfig/
  # autodiscover records for each.
  mail_domains = ["brawer.ch"]

  # Per-domain DKIM selector + Infomaniak-issued public key. A domain only
  # gets a DKIM record once it's been added in the Infomaniak mail admin and
  # the key is known - the other mail_domains records don't depend on this.
  mail_dkim = {
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

resource "bunnynet_dns_record" "spf" {
  for_each = toset(local.mail_domains)

  zone = bunnynet_dns_zone.this[each.value].id
  name = ""

  type  = "TXT"
  value = "v=spf1 include:spf.infomaniak.ch -all"
}

resource "bunnynet_dns_record" "autoconfig" {
  for_each = toset(local.mail_domains)

  zone = bunnynet_dns_zone.this[each.value].id
  name = "autoconfig"

  type  = "CNAME"
  value = "infomaniak.com"
}

resource "bunnynet_dns_record" "autodiscover" {
  for_each = toset(local.mail_domains)

  zone = bunnynet_dns_zone.this[each.value].id
  name = "autodiscover"

  type  = "CNAME"
  value = "infomaniak.com"
}

resource "bunnynet_dns_record" "dkim" {
  for_each = local.mail_dkim

  zone = bunnynet_dns_zone.this[each.key].id
  name = "${each.value.selector}._domainkey"

  type  = "TXT"
  value = each.value.value
}

# kube-shim control-plane (issue #36), on UpCloud (zone de-fra1, server uuid
# 003a02c7-6efb-4828-9227-97d6ac728964). Must resolve ahead of the shim's
# planned ACME/HTTP-01 integration (kube-shim IMPLEMENTATION_PLAN.md Phase 4).
resource "bunnynet_dns_record" "kube_shim_a" {
  zone = bunnynet_dns_zone.this["brawer.ch"].id
  name = "kube-shim"

  type  = "A"
  value = "94.237.90.144"
}

resource "bunnynet_dns_record" "kube_shim_aaaa" {
  zone = bunnynet_dns_zone.this["brawer.ch"].id
  name = "kube-shim"

  type  = "AAAA"
  value = "2a04:3542:1000:910:4086:11ff:fec4:17da"
}

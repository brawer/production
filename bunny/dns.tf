# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# DNS for dandelis.ch, hosted on Bunny DNS. After `tofu apply`, point the
# dandelis.ch nameservers at the values in the `dns_nameservers` output at the
# registrar. dandelis.ch is a parked domain with no records to migrate; add any
# MX/TXT/etc. here before switching nameservers.
resource "bunnynet_dns_zone" "dandelis" {
  domain = "dandelis.ch"
}

# One PullZone-type record per hostname, linked to the pull zone that serves it.
# Bunny resolves these to the CDN and provisions the managed TLS certificate.
resource "bunnynet_dns_record" "site" {
  for_each = local.site_hostnames

  zone        = bunnynet_dns_zone.dandelis.id
  name        = each.value.hostname == "dandelis.ch" ? "" : trimsuffix(each.value.hostname, ".dandelis.ch")
  type        = "PullZone"
  value       = bunnynet_pullzone.site[each.value.site].name
  pullzone_id = bunnynet_pullzone.site[each.value.site].id
}

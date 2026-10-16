# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

terraform {
  required_providers {
    upcloud = {
      source  = "UpCloudLtd/upcloud"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.6.0"
}

# Account-level credential that creates/manages the host itself (server,
# firewall) -- separate from the scoped runtime token in kube-shim.tf that
# the shim process itself uses to provision worker VMs. username/password,
# not the provider's own `token` argument: that one is still marked
# EXPERIMENTAL in the provider's own docs, username/password is the stable,
# documented mechanism.
provider "upcloud" {
  username = trimspace(file("${path.module}/../secrets/kube_shim_upcloud_username"))
  password = trimspace(file("${path.module}/../secrets/kube_shim_upcloud_password"))
}

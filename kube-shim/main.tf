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

# Main-account API token that creates/manages the host itself (server,
# firewall). Only ever used locally by `tofu apply`, never sent to the
# host -- separate from the sub-account runtime token in kube-shim.tf that
# the shim process itself uses to provision worker VMs. The provider's docs
# still mark `token` as EXPERIMENTAL; we use it anyway so that no account
# password has to sit in a file.
provider "upcloud" {
  token = trimspace(file("${path.module}/../secrets/kube_shim_upcloud_tofu_token"))
}

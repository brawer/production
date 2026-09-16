# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# DISABLED 2026-09-16: this module's cluster (kaas.tf) was torn down after
# a successful validation run - see README.md's Infomaniak section and git
# history for the full story. `min_instances = 1` means an always-on node
# bills continuously, so this stays off between real uses rather than
# sitting idle for no reason.
#
# Everything below (and all of kaas.tf, outputs.tf, and
# ../infomaniak-k8s's main.tf/osmdiffs.tf) is commented out rather than
# deleted, on purpose: with nothing declared in config, `tofu apply` here
# is a guaranteed no-op - it can't recreate real, billed infrastructure by
# accident. Deleting the code instead would leave the same directory ready
# to silently recreate everything on the next stray `apply`, since state is
# already empty and would just reconcile back to whatever the .tf files
# say.
#
# To use this again: uncomment this file and its counterparts (search this
# repo for "DISABLED 2026-09-16" to find all of them), then
# `tofu apply` in infomaniak/ first, `../infomaniak-k8s` second - see
# README.md's Usage section for the full sequence.
/*
terraform {
  required_providers {
    infomaniak = {
      source  = "Infomaniak/infomaniak"
      version = "~> 1.4"
    }
  }
  required_version = ">= 1.0"
}

# API token is read from secrets/infomaniak_api_token at the repo root
# (gitignored). Generate one at:
# https://www.infomaniak.com/en/support/faq/2582/generate-and-manage-infomaniak-api-tokens
provider "infomaniak" {
  token = trimspace(file("${path.module}/../secrets/infomaniak_api_token"))
}
*/

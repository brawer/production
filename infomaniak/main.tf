# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

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

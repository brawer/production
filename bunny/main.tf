# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

terraform {
  required_providers {
    bunnynet = {
      source  = "BunnyWay/bunnynet"
      version = "~> 0.18"
    }
  }
  required_version = ">= 1.0"
}

# API key is read from secrets/bunny_api_key at the repo root (gitignored).
provider "bunnynet" {
  api_key = trimspace(file("${path.module}/../secrets/bunny_api_key"))
}

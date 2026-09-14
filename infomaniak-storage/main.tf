# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# Infomaniak Public Cloud Object Storage is Swift with an S3-compatible API
# layer bolted on (docs: https://docs.infomaniak.cloud/object_storage/s3/).
# There's no dedicated Infomaniak Terraform resource for it (checked: the
# Infomaniak/infomaniak provider used in ../infomaniak has no object-storage
# resource, and object storage isn't in its account API at all - see the
# credentials comment below) - so this module talks to it like any other
# S3-compatible service (Cloudflare R2, MinIO, ...): the `aws` provider
# pointed at a custom endpoint, path-style addressing, region as a pure
# compatibility placeholder (all data stays in Infomaniak's Swiss DCs
# regardless of the region string).
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.0"
}

# Credentials are OpenStack EC2-style access/secret keys, NOT the Infomaniak
# account API token (secrets/infomaniak_api_token, used by ../infomaniak) -
# object storage isn't reachable through that account API at all. Generate
# them once (they don't need to change unless rotated):
#   1. Download the project's clouds.yaml (Manager -> Public Cloud -> your
#      project -> OpenStack API) to ~/.config/openstack/clouds.yaml.
#   2. `openstack ec2 credentials create` (installs via `pip install
#      python-openstackclient`) and save the two values it prints to
#      secrets/infomaniak_s3_access_key / secrets/infomaniak_s3_secret_key
#      (gitignored, no trailing newline).
provider "aws" {
  access_key = trimspace(file("${path.module}/../secrets/infomaniak_s3_access_key"))
  secret_key = trimspace(file("${path.module}/../secrets/infomaniak_s3_secret_key"))

  region = "us-east-1" # compatibility placeholder only, see above

  skip_credentials_validation = true
  skip_region_validation      = true
  skip_requesting_account_id  = true

  endpoints {
    s3 = "https://s3.pub1.infomaniak.cloud"
  }
}

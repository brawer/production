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
# object storage isn't reachable through that account API at all. Created by
# ../infomaniak-s3-auth (openstack_identity_ec2_credential_v3), read back
# via terraform_remote_state rather than a direct reference for the same
# reason infomaniak-k8s reads infomaniak's kubeconfig that way: provider
# config can't depend on a value only known after this same apply creates
# the resource it comes from.
data "terraform_remote_state" "infomaniak_s3_auth" {
  backend = "local"
  config = {
    path = "${path.module}/../infomaniak-s3-auth/terraform.tfstate"
  }
}

provider "aws" {
  access_key = data.terraform_remote_state.infomaniak_s3_auth.outputs.access
  secret_key = data.terraform_remote_state.infomaniak_s3_auth.outputs.secret

  region = "us-east-1" # compatibility placeholder only, see above

  skip_credentials_validation = true
  skip_region_validation      = true
  skip_requesting_account_id  = true

  # Required: Infomaniak's S3 layer doesn't support virtual-hosted-style
  # addressing (bucket.s3.pub1.infomaniak.cloud) - their own docs say to set
  # forcePathStyle=true "otherwise it may fail on some bucket operations".
  # Confirmed the hard way: omitting this made plain CreateBucket fail with
  # "InvalidBucketName" (TF_LOG=DEBUG showed aws.region=aws-global, i.e. the
  # SDK routing CreateBucket through its virtual-hosted-style global S3
  # endpoint logic instead of our custom one).
  s3_use_path_style = true

  endpoints {
    s3 = "https://s3.pub1.infomaniak.cloud"
  }
}

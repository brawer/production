# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# Authenticates to the osmdiffs Public Cloud project's OpenStack API so
# ../infomaniak-storage can get real S3 credentials without any manual
# browser/CLI step (the "download clouds.yaml, run `openstack ec2
# credentials create`" flow in Infomaniak's own docs). Separate module/state
# from infomaniak-storage for the same reason infomaniak-k8s is separate
# from infomaniak: the aws provider there can't be configured from a
# credential created in the same apply that creates it.
#
# Connection details below (auth_url, project id, username, domains,
# region) came from Infomaniak's account API, not a downloaded clouds.yaml:
#   token=$(cat ../secrets/infomaniak_api_token)
#   curl -s -H "Authorization: Bearer $token" \
#     "https://api.infomaniak.com/1/public_clouds/23824/projects/47516/users" \
#     | jq '.data[] | {id: .public_cloud_user_id, name: .open_stack_name}'
#   curl -s -H "Authorization: Bearer $token" \
#     "https://api.infomaniak.com/1/public_clouds/23824/projects/47516/users/<user_id>/openrc?region=pub1"
#   # -> {"result":"delayed","data":"<task_uuid>"}; poll:
#   curl -s -H "Authorization: Bearer $token" \
#     "https://api.infomaniak.com/1/async/tasks/<task_uuid>"
#   # -> .data.response.data is the openrc shell script (OS_AUTH_URL etc.)
terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4"
    }
  }
  required_version = ">= 1.0"
}

locals {
  auth_url            = "https://api.pub1.infomaniak.cloud/identity/v3"
  user_name           = "PCU-SSOT8WN"
  user_domain_name    = "default"
  project_domain_name = "default"
  tenant_id           = "94641c761a454e58b221b309701db850"
  region              = "dc3-a"
}

# The one non-Terraform-managed bootstrap step (like the Public Cloud
# project's own creation): this project's OpenStack user had no password
# set, so Terraform couldn't authenticate as it. Set once via the same
# account API - the Infomaniak/infomaniak provider has no resource for
# this user, so it can't be brought under Terraform management itself:
#   curl -s -X PATCH -H "Authorization: Bearer $token" \
#     -H "Content-Type: application/json" \
#     -d '{"password": "<new password>"}' \
#     "https://api.infomaniak.com/1/public_clouds/23824/projects/47516/users/71332"
# Whoever rotates secrets/infomaniak_openstack_password needs to run that
# PATCH with the new value too, or auth here breaks.
provider "openstack" {
  auth_url            = local.auth_url
  user_name           = local.user_name
  user_domain_name    = local.user_domain_name
  project_domain_name = local.project_domain_name
  tenant_id           = local.tenant_id
  region              = local.region

  password = trimspace(file("${path.module}/../secrets/infomaniak_openstack_password"))
}

# A real EC2-style access/secret key pair in Keystone, scoped to this
# project (the provider's current auth scope) - exactly what `openstack ec2
# credentials create` does, via Terraform instead of a manual CLI step.
resource "openstack_identity_ec2_credential_v3" "s3" {}

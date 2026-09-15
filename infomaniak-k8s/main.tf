# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# Kubernetes-level resources (CronJob, Secret) for the cluster created in
# ../infomaniak. Deliberately a separate root module/state: configuring the
# kubernetes provider from that cluster's own (not-yet-known-at-plan-time)
# kubeconfig output, in the same apply that creates the cluster, is a known
# Terraform footgun. Reading it back from ../infomaniak's already-applied
# state via `terraform_remote_state` avoids that.
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.0"
}

data "terraform_remote_state" "infomaniak" {
  backend = "local"
  config = {
    path = "${path.module}/../infomaniak/terraform.tfstate"
  }
}

# The cronjob's two S3 destinations (see cronjob.tf) are both already
# Terraform-managed elsewhere - read their credentials back the same way
# infomaniak-storage reads infomaniak-s3-auth's, rather than duplicating
# them into a separate secrets file.
data "terraform_remote_state" "bunny" {
  backend = "local"
  config = {
    path = "${path.module}/../bunny/terraform.tfstate"
  }
}

data "terraform_remote_state" "infomaniak_s3_auth" {
  backend = "local"
  config = {
    path = "${path.module}/../infomaniak-s3-auth/terraform.tfstate"
  }
}

# UNVERIFIED: assumes the kubeconfig Infomaniak returns is a standard
# client-certificate kubeconfig (single cluster/user - the common shape for
# managed Kubernetes offerings). Confirm once the cluster actually exists
# (`tofu -chdir=../infomaniak output -raw kubeconfig`); if Infomaniak instead
# hands out a bearer token, swap client_certificate/client_key below for a
# `token` field.
locals {
  kaas_kubeconfig = yamldecode(data.terraform_remote_state.infomaniak.outputs.kubeconfig)
  kaas_cluster    = local.kaas_kubeconfig.clusters[0].cluster
  kaas_user       = local.kaas_kubeconfig.users[0].user
}

provider "kubernetes" {
  host                   = local.kaas_cluster.server
  cluster_ca_certificate = base64decode(local.kaas_cluster["certificate-authority-data"])
  client_certificate     = base64decode(local.kaas_user["client-certificate-data"])
  client_key             = base64decode(local.kaas_user["client-key-data"])
}

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# Kubernetes-level resources (CronJobs, Secrets) scheduled on kube-shim
# (../kube-shim), which runs each job on its own short-lived UpCloud worker
# VM. A separate root module/state from ../kube-shim on purpose, for the
# same reason ../infomaniak-k8s is separate from ../infomaniak: configuring
# the kubernetes provider from credentials created in the same apply is a
# known Terraform footgun.
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.6.0"
}

# The bearer token is read back from ../kube-shim's own state rather than
# copied into a secrets/ file, the same way ../infomaniak-k8s reads its
# credentials: no second copy to drift or leak, and a token rotation in
# ../kube-shim is picked up here on the next plan.
data "terraform_remote_state" "kube_shim" {
  backend = "local"
  config = {
    path = "${path.module}/../kube-shim/terraform.tfstate"
  }
}

# The osmdiffs job's two S3 destinations are Terraform-managed elsewhere in
# this repo; see osmdiffs.tf.
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

# kube-shim serves a publicly trusted Let's Encrypt certificate, so no
# cluster_ca_certificate is needed.
provider "kubernetes" {
  host  = "https://kube-shim.brawer.ch"
  token = data.terraform_remote_state.kube_shim.outputs.api_tokens["kube-shim-jobs"]
}

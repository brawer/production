# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# Managed Kubernetes (KaaS) cluster to run scheduled batch jobs on - see
# infomaniak-k8s/osmdiffs.tf for the actual workload. Lives inside an existing
# Infomaniak Public Cloud project; this provider has no resource to create
# that project itself (Manager -> Public Cloud -> create project), so the
# project must already exist before applying this.
locals {
  public_cloud_id         = 23824
  public_cloud_project_id = 47516

  # Verified against the real API (GET /1/public_clouds/kaas/regions and
  # .../versions, with secrets/infomaniak_api_token): "dc-4" (a guess from
  # the Manager UI's "Data Center 4" label) was wrong - the actual slug is
  # "dc4-a" (the other option is "dc3-a"). 1.36 is confirmed offered
  # (available: 1.36, 1.35, 1.34, 1.33, 1.32).
  kaas_region             = "dc4-a"
  kaas_kubernetes_version = "1.36"
}

# pack_name = "shared" is the public/shared control plane, which is free; a
# dedicated control plane is billed separately. Only the worker nodes below
# (instance pool) cost anything.
resource "infomaniak_kaas" "cronjobs" {
  public_cloud_id         = local.public_cloud_id
  public_cloud_project_id = local.public_cloud_project_id

  name               = "cronjobs"
  pack_name          = "shared"
  kubernetes_version = local.kaas_kubernetes_version
  region             = local.kaas_region
}

# One node pool. The cronjob it exists for (infomaniak-k8s/osmdiffs.tf) runs
# ~3h once a week, so a fixed always-on node would sit idle >99% of the
# time - min_instances = 0 was the intent (scale to zero when idle, autoscale
# a node back up when the CronJob's Job is pending), but it doesn't work:
# CONFIRMED (2026-09, real apply) the API rejects it - "The maximum
# instances must be greater than or equal minimum instances. The minimum
# instances field is required." - min_instances = 0 in the request body is
# apparently indistinguishable from "not set" (a Go zero-value/omitempty
# thing on either the provider or API side), so the required-field check
# fails. min_instances = 1 is the confirmed-working fallback: one node runs
# at all times, at flavor_name's ~$0.0374/h ($27/month) rather than only
# ~$0.45/month for the actual weekly runtime.
resource "infomaniak_kaas_instance_pool" "cronjobs" {
  public_cloud_id         = infomaniak_kaas.cronjobs.public_cloud_id
  public_cloud_project_id = infomaniak_kaas.cronjobs.public_cloud_project_id
  kaas_id                 = infomaniak_kaas.cronjobs.id

  name = "cronjobs"

  # Smallest flavor from GET .../kaas/flavors?region=dc4-a that clears the
  # cronjob's 6 vCPU / 8 GiB request (infomaniak-k8s/osmdiffs.tf) with real
  # headroom for kubelet/system overhead - double the RAM request, not an
  # exact match (a flavor sized exactly to the request would likely leave
  # the pod unschedulable).
  flavor_name = "a8-ram16-disk20-perf1"

  # One of az-1/az-2/az-3 (GET .../kaas/availability_zones?region=dc4-a) -
  # arbitrary pick, no cross-AZ requirement for a single-node pool.
  availability_zone = "az-1"

  min_instances = 1
  max_instances = 2
}

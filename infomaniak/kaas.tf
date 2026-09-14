# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# Managed Kubernetes (KaaS) cluster to run scheduled batch jobs on - see
# infomaniak-k8s/cronjob.tf for the actual workload. Lives inside an existing
# Infomaniak Public Cloud project; this provider has no resource to create
# that project itself (Manager -> Public Cloud -> create project), so the
# project must already exist before applying this.
locals {
  public_cloud_id         = 23824
  public_cloud_project_id = 47516

  # UNVERIFIED: "Data Center 4" is the label shown in the Manager UI: the
  # provider's own examples use short API slugs instead (e.g. "dc-3"), so
  # this may need to become one of those instead. Region/version are only
  # checked against the real API at apply time (`tofu validate` can't catch
  # a wrong value here) - if `tofu apply` rejects it, find the actual slug
  # via `openstack region list` (project's clouds.yaml) or the cluster
  # creation screen in Manager -> Public Cloud -> Kubernetes.
  kaas_region = "Data Center 4"

  # UNVERIFIED: whether Infomaniak's KaaS offering has 1.36 available yet -
  # same apply-time caveat as region.
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

# One node pool, scaled to zero when idle: the cronjob it exists for
# (infomaniak-k8s/cronjob.tf) runs ~4h once a week, so a fixed always-on node
# would sit idle >99% of the time. min_instances = 0 asks the cluster
# autoscaler to remove the last node once nothing needs it and add one back
# when the CronJob's Job is scheduled.
#
# UNVERIFIED: whether Infomaniak's autoscaler actually supports scaling from
# zero (some managed-Kubernetes autoscalers need at least one node to observe
# a pending pod). Watch the first scheduled run to confirm before relying on
# it; the fallback is min_instances = 1.
resource "infomaniak_kaas_instance_pool" "cronjobs" {
  public_cloud_id         = infomaniak_kaas.cronjobs.public_cloud_id
  public_cloud_project_id = infomaniak_kaas.cronjobs.public_cloud_project_id
  kaas_id                 = infomaniak_kaas.cronjobs.id

  name = "cronjobs"

  # TODO: pick a flavor with >= 8 vCPUs / >= 8 GiB RAM (the cronjob's
  # requirements - see infomaniak-k8s/cronjob.tf) from `openstack flavor
  # list` (using the project's clouds.yaml) or Manager -> Public Cloud ->
  # Compute -> Flavors. Infomaniak's naming looks like "a1-ram2-disk20-perf1"
  # (class+vCPUs, RAM GiB, disk GiB, perf tier).
  flavor_name = "TODO"

  # TODO: verify against `openstack availability zone list` for this project.
  availability_zone = "TODO"

  min_instances = 0
  max_instances = 2
}

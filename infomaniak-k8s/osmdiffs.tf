# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# Weekly batch job: the osmdiffs pipeline (brawer/osmdiffs) - see
# https://github.com/brawer/osmdiffs/blob/main/docs/PRODUCTION.md for the
# authoritative env vars, invocation, and resource requirements this file
# follows. Named osmdiffs_* / osmdiffs-* throughout (not e.g. "cronjob_*")
# since this cluster (../infomaniak) is meant to host more than one
# project's scheduled job over time - keep each project's Kubernetes
# objects distinctly named so they don't collide or get confused.
#
# TODO before first apply:
#  - image/command: replace the busybox placeholder with the real job.
#  - storage_class_name: verify with `kubectl get storageclass` once the
#    cluster exists - Infomaniak's CSI Cinder driver's default class name is
#    unverified here.
locals {
  # The pipeline needs two independent S3 destinations (PRODUCTION.md):
  # PUBLIC_S3_* for downloads via CDN, INTERNAL_S3_* for logs/intermediates.
  # Both are already Terraform-managed elsewhere in this repo - PUBLIC_S3_*
  # is Bunny's existing osmdiffs-data-de storage zone (bunny/storage.tf,
  # the same one osmdiffs-app's data pull zone fronts), INTERNAL_S3_* is
  # ../infomaniak-storage's osmdiffs-internal bucket, authenticated via
  # ../infomaniak-s3-auth's credential. Bucket/endpoint names aren't secret,
  # but PRODUCTION.md is explicit that all of these should be handled as
  # secrets, not plain config - so everything goes in the one Secret below
  # rather than splitting into an env_from + separate plain env vars.
  #
  # UNVERIFIED: the *_REGION values. Neither S3-compatible endpoint has a
  # real AWS-style region; "DE" matches Bunny's own storage-zone region code
  # (local.storage_zones["osmdiffs-data-de"].region in bunny/storage.tf) and
  # "us-east-1" is the same compatibility placeholder used everywhere else
  # in this repo for Infomaniak's S3 layer (infomaniak-storage/main.tf) -
  # correct if the pipeline's S3 client just needs a non-empty string, wrong
  # if it actually validates/uses the region. Check on the first real run.
  osmdiffs_s3_env = {
    PUBLIC_S3_ENDPOINT          = data.terraform_remote_state.bunny.outputs.s3_endpoints["osmdiffs-data-de"]
    PUBLIC_S3_BUCKET            = "osmdiffs-data-de"
    PUBLIC_S3_REGION            = "DE"
    PUBLIC_S3_ACCESS_KEY_ID     = "osmdiffs-data-de" # Bunny: access key ID = zone name
    PUBLIC_S3_ACCESS_KEY_SECRET = data.terraform_remote_state.bunny.outputs.passwords["osmdiffs-data-de"]

    INTERNAL_S3_ENDPOINT          = "https://s3.pub1.infomaniak.cloud"
    INTERNAL_S3_BUCKET            = "osmdiffs-internal"
    INTERNAL_S3_REGION            = "us-east-1"
    INTERNAL_S3_ACCESS_KEY_ID     = data.terraform_remote_state.infomaniak_s3_auth.outputs.access
    INTERNAL_S3_ACCESS_KEY_SECRET = data.terraform_remote_state.infomaniak_s3_auth.outputs.secret
  }
}

resource "kubernetes_secret_v1" "osmdiffs_s3_credentials" {
  metadata {
    name = "osmdiffs-s3-credentials"
  }

  data = local.osmdiffs_s3_env
}

resource "kubernetes_cron_job_v1" "osmdiffs" {
  metadata {
    name = "osmdiffs-weekly"
  }

  spec {
    schedule = "0 3 * * 0" # 03:00 UTC every Sunday

    concurrency_policy            = "Forbid" # never overlap a multi-hour run
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3
    starting_deadline_seconds     = 3600 # skip a run rather than pile up if the cluster was down

    job_template {
      metadata {}
      spec {
        backoff_limit           = 1
        active_deadline_seconds = 6 * 3600 # hard stop at 6h; job takes ~3-4h

        template {
          metadata {}
          spec {
            restart_policy = "Never"

            container {
              name    = "osmdiffs"
              image   = "busybox" # TODO: replace with the real image
              command = ["/bin/sh", "-c", "echo TODO: replace with the real command"]

              resources {
                requests = {
                  cpu    = "8"
                  memory = "8Gi"
                }
                limits = {
                  cpu    = "8"
                  memory = "8Gi"
                }
              }

              env_from {
                secret_ref {
                  name = kubernetes_secret_v1.osmdiffs_s3_credentials.metadata[0].name
                }
              }

              volume_mount {
                name       = "scratch"
                mount_path = "/scratch"
              }
            }

            volume {
              name = "scratch"

              # An ephemeral (inline) PVC: created fresh for each Job's pod
              # and deleted with it, so a stale scratch volume never lingers
              # between weekly runs.
              ephemeral {
                volume_claim_template {
                  spec {
                    access_modes = ["ReadWriteOnce"]

                    # TODO: verify this is the cluster's actual default/CSI
                    # storage class name once it exists.
                    storage_class_name = "csi-cinder-high-speed"

                    resources {
                      requests = {
                        storage = "200Gi"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

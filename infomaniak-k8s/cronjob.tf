# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# Weekly batch job: 8 vCPUs / 8 GiB RAM, ~3-4h runtime, 200 GiB of ephemeral
# scratch space, reads/writes several S3 buckets using the credentials in
# cronjob_s3_credentials below.
#
# TODO before first apply:
#  - image/command: replace the busybox placeholder with the real job.
#  - secrets/infomaniak_cronjob_s3_credentials.json: create with the real
#    credentials (see cronjob_s3_credentials below).
#  - storage_class_name: verify with `kubectl get storageclass` once the
#    cluster exists - Infomaniak's CSI Cinder driver's default class name is
#    unverified here.
locals {
  # S3 credentials the job needs, as environment variables - a flat string
  # map in secrets/infomaniak_cronjob_s3_credentials.json (gitignored), e.g.:
  #   {"OSMVIEWS_S3_SECRET_KEY": "...", "OSMDIFFS_S3_SECRET_KEY": "..."}
  # Matching access-key IDs / bucket names aren't secret and can just be
  # plain env vars on the container instead (env_from only carries the
  # secret ones).
  cronjob_s3_credentials = jsondecode(file("${path.module}/../secrets/infomaniak_cronjob_s3_credentials.json"))
}

resource "kubernetes_secret_v1" "cronjob_s3_credentials" {
  metadata {
    name = "cronjob-s3-credentials"
  }

  data = local.cronjob_s3_credentials
}

resource "kubernetes_cron_job_v1" "weekly" {
  metadata {
    name = "weekly-batch-job"
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
              name    = "job"
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
                  name = kubernetes_secret_v1.cronjob_s3_credentials.metadata[0].name
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

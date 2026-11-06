# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# Weekly batch job: the osmdiffs pipeline (brawer/osmdiffs). Follows
# https://github.com/brawer/osmdiffs/blob/main/docs/PRODUCTION.md for env
# vars, invocation and sizing. Ported from ../infomaniak-k8s/osmdiffs.tf
# (disabled since 2026-09-16), which ran it successfully on Infomaniak
# Kubernetes; the comments there record what that run confirmed.
#
# Needs kube-shim v0.3.1+ (brawer/kube-shim#84, #85, #86, #92). kube-shim
# doesn't implement `suspend`, so applying schedules runs right away. See
# README.md's "kube-shim jobs" section.

locals {
  # Two independent S3 destinations (PRODUCTION.md): PUBLIC_S3_* for the
  # downloads behind the CDN (Bunny's osmdiffs-data-de storage zone,
  # bunny/storage.tf), INTERNAL_S3_* for logs (../infomaniak-storage's
  # osmdiffs-internal bucket, credential from ../infomaniak-s3-auth).
  # PRODUCTION.md asks for all of these to be handled as secrets, so they
  # all go in the one Secret below.
  #
  # Regions must be lowercase: the pipeline's S3 client rejects anything
  # else, and only at the very last step of a multi-hour run (confirmed on
  # Infomaniak). "de" is Bunny's region code "DE" lowercased; "us-east-1"
  # is the placeholder used for Infomaniak's S3 layer throughout this repo.
  osmdiffs_s3_env = {
    PUBLIC_S3_ENDPOINT          = data.terraform_remote_state.bunny.outputs.s3_endpoints["osmdiffs-data-de"]
    PUBLIC_S3_BUCKET            = "osmdiffs-data-de"
    PUBLIC_S3_REGION            = "de"
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
    starting_deadline_seconds     = 3600 # skip a run rather than pile up

    job_template {
      metadata {}
      spec {
        backoff_limit = 1

        # Required by kube-shim (it bounds a job's worst-case cost for the
        # budget guard). The real Infomaniak run took 5h55m, and a 6h
        # deadline there killed a run that was still legitimately working;
        # 16h stays generous until runs on UpCloud give a real number.
        active_deadline_seconds = 16 * 3600

        template {
          metadata {}
          spec {
            restart_policy = "Never"

            # The image runs as UID 1000, but a freshly formatted scratch
            # volume is owned by root; without this the pipeline fails on
            # its first write (confirmed on Infomaniak). Any fixed GID works.
            security_context {
              fs_group = "1000"
            }

            container {
              name = "osmdiffs"

              # `latest` is pushed by osmdiffs' release workflow together
              # with each vX.Y.Z tag (v0.8.10 as of 2026-11-06). Each
              # kube-shim job runs on a brand-new worker VM, so the image is
              # pulled at job start and every run gets the newest release.
              # PRODUCTION.md recommends pinning; to pin, use e.g. ":v0.8.10".
              image = "ghcr.io/brawer/osmdiffs:latest"

              # The image's ENTRYPOINT is the osmdiffs binary. $(RUN_ID) is
              # Kubernetes' env-var substitution in args (no shell needed).
              args = ["run", "--workdir", "/scratch", "--run_id", "$(RUN_ID)"]

              # The pod's name: unique per run, and already within the
              # [A-Za-z0-9._-] character set --run_id wants.
              env {
                name = "RUN_ID"
                value_from {
                  field_ref {
                    field_path = "metadata.name"
                  }
                }
              }

              # PRODUCTION.md's recommended minimum (6 CPU / 8 GB).
              resources {
                requests = {
                  cpu    = "6"
                  memory = "8Gi"
                }
                limits = {
                  cpu    = "6"
                  memory = "8Gi"
                }
              }

              # PRODUCTION.md runs the image with --read-only; the scratch
              # volume is the only writable path the pipeline needs.
              security_context {
                read_only_root_filesystem = true
              }

              env_from {
                secret_ref {
                  name = kubernetes_secret_v1.osmdiffs_s3_credentials.metadata[0].name
                }
              }

              # /scratch rather than PRODUCTION.md's /workdir: kube-shim's
              # default mount point. (Since v0.3.0 kube-shim honors
              # mount_path, so /workdir would work too.)
              volume_mount {
                name       = "scratch"
                mount_path = "/scratch"
              }
            }

            volume {
              name = "scratch"

              # Ephemeral: created fresh for each run and deleted with it.
              ephemeral {
                volume_claim_template {
                  spec {
                    access_modes = ["ReadWriteOnce"]

                    # MaxIOPS rather than kube-shim-standard: PRODUCTION.md
                    # suspects slow network storage of doubling the
                    # Infomaniak runtime, and the pipeline uses its scratch
                    # disk heavily. About EUR 0.47 vs 0.18 per 6h run for
                    # 250 GB; revisit once real UpCloud timings exist.
                    storage_class_name = "kube-shim-fast"

                    # PRODUCTION.md: peak ~172 GB, recommends 220-250 GB.
                    resources {
                      requests = {
                        storage = "250Gi"
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

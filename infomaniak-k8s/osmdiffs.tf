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

            # CONFIRMED via a real test run: the image runs as a fixed
            # non-root UID (1000 - see brawer/osmdiffs#812), but the
            # Cinder-backed ephemeral volume mounts owned by root - without
            # this, the container fails immediately
            # ("failed to open log file /workdir/pipeline.log: Permission
            # denied"). fs_group makes the kubelet chown the volume to this
            # GID and adds it as a supplemental group on the container's
            # process, regardless of the image's own /etc/group - doesn't
            # need to be the image's real GID (unknown), any fixed value
            # works, so this just matches the known UID.
            security_context {
              fs_group = "1000"
            }

            container {
              name  = "osmdiffs"
              image = "ghcr.io/brawer/osmdiffs:v0.8.5"

              # No `command`: the image's own ENTRYPOINT is the osmdiffs
              # binary (PRODUCTION.md's invocation is
              # `osmdiffs run --workdir /workdir --run_id "$RUN_ID"`), so
              # only the args need setting here. $(RUN_ID) is Kubernetes'
              # native env-var substitution in command/args (no shell
              # needed) - see the RUN_ID env var below.
              args = ["run", "--workdir", "/workdir", "--run_id", "$(RUN_ID)"]

              # PRODUCTION.md: "--run_id: identifier for provenance
              # tracking (normalized to [A-Za-z0-9._-])". The pod's own
              # name is unique per run (CronJob -> Job -> Pod, each with a
              # generated suffix) and already fits that character set.
              env {
                name = "RUN_ID"
                value_from {
                  field_ref {
                    field_path = "metadata.name"
                  }
                }
              }

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

              # PRODUCTION.md's invocation runs with `--read-only` (immutable
              # root filesystem); /workdir below is the only writable path
              # the pipeline needs.
              security_context {
                read_only_root_filesystem = true
              }

              env_from {
                secret_ref {
                  name = kubernetes_secret_v1.osmdiffs_s3_credentials.metadata[0].name
                }
              }

              volume_mount {
                name       = "workdir"
                mount_path = "/workdir"
              }
            }

            volume {
              name = "workdir"

              # An ephemeral (inline) PVC: created fresh for each Job's pod
              # and deleted with it, so a stale scratch volume never lingers
              # between weekly runs.
              ephemeral {
                volume_claim_template {
                  spec {
                    access_modes = ["ReadWriteOnce"]

                    # CONFIRMED via `kubectl get storageclass` once the
                    # cluster existed: real classes are csi-cinder-sc-delete
                    # and csi-cinder-sc-retain (the default) -
                    # "csi-cinder-high-speed" (guessed from the naming
                    # pattern before the cluster existed) was wrong. -delete
                    # is the right one here regardless of which is default:
                    # it matches this volume's actual lifecycle (deleted
                    # with the pod each run, see the ephemeral comment
                    # above) - -retain would silently leak a Cinder volume
                    # every week.
                    storage_class_name = "csi-cinder-sc-delete"

                    # PRODUCTION.md: peak ~172GB during a run, settling to
                    # ~143GB after; recommends 220-250GB capacity headroom.
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

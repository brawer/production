# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# Buckets for scheduled batch jobs: logs and caches carried between runs.
# Not for the public downloads, which go through Bunny (../bunny's /data/*
# CDN).
#
# Each bucket is a Swift container. Infomaniak's S3 layer (used by the jobs
# themselves, with the credential from ../infomaniak-s3-auth) can't set
# Swift ACLs: put-bucket-acl --acl public-read reports success but changes
# nothing. So the containers are managed through the OpenStack provider,
# which sets X-Container-Read directly.
#
#   project     - which project's workload this bucket belongs to (a label).
#   public_read - true makes the bucket world-readable and listable
#                 (".r:*,.rlistings"), anonymously, over the Swift URL in
#                 the public_urls output. Never writable without a key.
#                 Only for content that's fine to publish.
locals {
  buckets = {
    "osmdiffs-internal" = {
      # Logs (logs/<job>.log) from the weekly osmdiffs CronJob in
      # ../kube-shim-jobs. Public since 2026-11-10: nothing in them is
      # confidential (input URLs, timings, memory and feature counts), and
      # public read lets Claude Code sessions, including cloud ones, read
      # them without any credential.
      project     = "osmdiffs"
      public_read = true
    }
  }
}

resource "openstack_objectstorage_container_v1" "this" {
  for_each = local.buckets

  name           = each.key
  storage_policy = "Policy-0" # Infomaniak's default; changing it replaces the container
  container_read = each.value.public_read ? ".r:*,.rlistings" : null
  # As Infomaniak sets it on containers created through the S3 API; kept
  # unchanged so writes still need the project's own credentials.
  container_write = "."
}

# The container was created through the S3 API as aws_s3_bucket.this (until
# 2026-11-10). Adopt it here, and drop the old resource from state without
# deleting the bucket.
import {
  for_each = local.buckets
  to       = openstack_objectstorage_container_v1.this[each.key]
  id       = each.key
}

removed {
  from = aws_s3_bucket.this

  lifecycle {
    destroy = false # forget only; the bucket lives on as the container above
  }
}

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# Internal-only buckets: not for public downloads (that's Bunny - see
# ../bunny's /data/* download CDN) but scratch space for scheduled batch
# jobs - logs and caches carried between runs. Private by default (a Swift
# container needs an explicit public-read policy/ACL to be public, which
# nothing here sets); "public_access_block"-style hardening isn't included
# since Infomaniak's S3 compatibility layer doesn't implement every AWS-only
# API (docs: "some features are not available") and that one is unverified
# here - revisit once buckets exist to check `aws s3api get-bucket-acl`.
#
#   project - which project's workload this bucket belongs to. Currently
#             just a label (no shared config depends on it), but keeps the
#             mapping to consumers (e.g. ../infomaniak-k8s's cronjob)
#             explicit as more buckets get added here.
locals {
  buckets = {
    "osmdiffs-internal" = {
      project = "osmdiffs" # logs/caches for the weekly cronjob, ../infomaniak-k8s
    }
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket = each.key
}

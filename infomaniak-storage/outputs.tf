# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

output "bucket_names" {
  description = "Map of bucket key => actual bucket name (identical here, but keeps consumers keyed the same way as local.buckets)."
  value       = { for k, b in aws_s3_bucket.this : k => b.bucket }
}

output "s3_endpoint" {
  description = "S3-compatible endpoint for all buckets in this module."
  value       = "https://s3.pub1.infomaniak.cloud"
}

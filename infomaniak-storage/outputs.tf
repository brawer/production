# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

output "bucket_names" {
  description = "Map of bucket key => actual bucket name (identical here, but keeps consumers keyed the same way as local.buckets)."
  value       = { for k, b in openstack_objectstorage_container_v1.this : k => b.name }
}

output "s3_endpoint" {
  description = "S3-compatible endpoint for all buckets in this module."
  value       = "https://s3.pub1.infomaniak.cloud"
}

output "public_urls" {
  description = "Anonymous read and list URL (Swift API) for each public_read bucket. Objects are at <url>/<key>; append ?format=json to list."
  value = {
    for k, b in openstack_objectstorage_container_v1.this :
    k => "https://s3.pub1.infomaniak.cloud/object/v1/AUTH_94641c761a454e58b221b309701db850/${b.name}"
    if local.buckets[k].public_read
  }
}

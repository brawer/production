# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

output "public_ipv4" {
  description = "Update bunny/dns.tf's kube_shim_a record to this value, then `cd ../bunny && tofu apply`."
  value       = module.kube_shim.public_ipv4
}

output "public_ipv6" {
  description = "Update bunny/dns.tf's kube_shim_aaaa record to this value, then `cd ../bunny && tofu apply`."
  value       = module.kube_shim.public_ipv6
}

output "server_id" {
  value = module.kube_shim.server_id
}

output "api_tokens" {
  description = "Bearer tokens for kube-shim's authenticated API, as a map keyed by the names in kube-shim.tf's api_tokens. \"kube-shim-jobs\" is read by ../kube-shim-jobs through remote state; save \"operator\" in a password manager (not another file in this repo) for your own kubectl/curl."
  value       = module.kube_shim.api_tokens
  sensitive   = true
}

output "worker_ssh_public_key" {
  value = module.kube_shim.worker_ssh_public_key
}

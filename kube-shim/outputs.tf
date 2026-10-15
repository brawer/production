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
  description = "Bearer token(s) for kube-shim's authenticated API. Not used by anything in this repo yet -- save at least api_tokens[0] somewhere (a password manager, not another file in this repo) for your own kubectl/Terraform client config against the instance."
  value       = module.kube_shim.api_tokens
  sensitive   = true
}

output "worker_ssh_public_key" {
  value = module.kube_shim.worker_ssh_public_key
}

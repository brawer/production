# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

output "kaas_id" {
  description = "Infomaniak KaaS cluster ID."
  value       = infomaniak_kaas.cronjobs.id
}

# Consumed by ../infomaniak-k8s via a local `terraform_remote_state` data
# source, so the kubernetes provider there can talk to this cluster without
# provider config depending on a not-yet-known resource attribute within a
# single apply (that pattern is unreliable - see
# https://developer.hashicorp.com/terraform/language/providers/configuration#provider-configuration).
#
# Same caveat as bunny/'s zone passwords: this ends up in
# infomaniak/terraform.tfstate in plaintext. It's gitignored - keep it
# private.
output "kubeconfig" {
  description = "Kubeconfig for the KaaS cluster. KEEP SECRET."
  value       = infomaniak_kaas.cronjobs.kubeconfig
  sensitive   = true
}

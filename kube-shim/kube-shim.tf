# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Sascha Brawer

# kube-shim control-plane (issue #36 originally; this module replaces the
# hand-provisioned instance from that issue with one built from
# github.com/brawer/kube-shim//tofu/upcloud -- see that module's own README
# for what it automates and what it deliberately doesn't). The previous
# instance's credentials (both server.api_tokens bearer tokens and its
# [upcloud] runtime token) are being treated as compromised and are not
# reused anywhere here -- this module mints entirely fresh ones.
module "kube_shim" {
  # Pinned to a release tag, not main: this module mints credentials and
  # decides what runs on the host, so an upstream merge shouldn't reach a
  # later `tofu init`/`apply` unnoticed. Bump deliberately; most upstream
  # changes alter user_data, which replaces the server (see README.md).
  source = "github.com/brawer/kube-shim//tofu/upcloud?ref=v0.2.8"

  hostname = "kube-shim.brawer.ch"

  # Reuses the existing deploy keypair (secrets/kube-shim-deploy_ed25519 in
  # the kube-shim repo) -- that key itself was never part of either
  # compromise, only the bearer/runtime tokens above were, so there's no
  # reason to cycle it too.
  operator_ssh_public_keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBjHt2bDhd0+UH0XYtsUb1UrTiuucn295RdNEl9dXV6c kube-shim.brawer.ch deploy key"
  ]

  # A dedicated UpCloud sub-account token, scoped to API access only -- NOT
  # the same account-level username/password main.tf's provider block
  # authenticates with. See the module's own variables.tf for why
  # (UpCloud's OpenTofu provider has no resource to mint this for us).
  upcloud_runtime_token = trimspace(file("${path.module}/../secrets/kube_shim_upcloud_runtime_token"))

  # Matches the previous instance's real, live settings at the time it was
  # decommissioned (EUR, budget guard disabled) -- a faithful like-for-like
  # restart, not a silent behavior change. Raise budget_daily_rate above 0
  # once ready to re-enable the guard.
  main_currency     = "EUR"
  budget_daily_rate = 0

  # "production" from the very first apply, not the module's "staging"
  # default: user_data is RequiresReplace in the UpCloud provider, so
  # flipping this later would destroy and recreate the host (new IPs, DNS
  # broken again). Until DNS points here, kube-shim's cold-start ACME
  # timeout + systemd's Restart=on-failure just keep retrying. See the
  # "## kube-shim" runbook in the top-level README.md.
  acme_directory = "production"
}

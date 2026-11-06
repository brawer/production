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
  # later `tofu init`/`apply` unnoticed. Bump deliberately, together with
  # image_tag below. Since v0.3.4 the module ignores user_data changes on
  # an existing host and pushes config.toml and the quadlet unit over SSH
  # instead, so a bump updates the host in place (see README.md).
  source = "github.com/brawer/kube-shim//tofu/upcloud?ref=v0.3.4"

  # The kube-shim container release to run. Pinned rather than "latest",
  # which also drops podman's AutoUpdate=registry: the host changes version
  # only when this value changes. Keep it in step with `source`.
  image_tag = "v0.3.4"

  # operator_ssh_private_key is left null, so `tofu apply` pushes over SSH
  # with whatever key your SSH agent holds; that must be the deploy key
  # below (see README.md's "Upgrading kube-shim").

  hostname = "kube-shim.brawer.ch"

  # Reuses the existing deploy keypair (secrets/kube-shim-deploy_ed25519 in
  # the kube-shim repo) -- that key itself was never part of either
  # compromise, only the bearer/runtime tokens above were, so there's no
  # reason to cycle it too.
  operator_ssh_public_keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBjHt2bDhd0+UH0XYtsUb1UrTiuucn295RdNEl9dXV6c kube-shim.brawer.ch deploy key"
  ]

  # A dedicated UpCloud sub-account token (brawer_kubeshim, see README.md)
  # -- NOT the main-account token main.tf's provider block authenticates
  # with, since this one gets stored on the host. UpCloud's OpenTofu
  # provider has no resource to mint this for us (see the module's own
  # variables.tf).
  upcloud_runtime_token = trimspace(file("${path.module}/../secrets/kube_shim_upcloud_runtime_token"))

  # Matches the previous instance's real, live settings at the time it was
  # decommissioned (EUR, budget guard disabled) -- a faithful like-for-like
  # restart, not a silent behavior change. Raise budget_daily_rate above 0
  # once ready to re-enable the guard.
  main_currency     = "EUR"
  budget_daily_rate = 0

  # "production" from the very first apply, not the module's "staging"
  # default, so a fresh host never serves an untrusted certificate. (Since
  # v0.3.4 changing it later would be pushed in place over SSH rather than
  # replacing the host.) Until DNS points at a brand-new host, kube-shim's
  # cold-start ACME timeout + systemd's Restart=on-failure just keep
  # retrying. See the "## kube-shim" runbook in the top-level README.md.
  acme_directory = "production"
}

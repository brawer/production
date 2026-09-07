<!--
SPDX-License-Identifier: MIT
SPDX-FileCopyrightText: 2026 Sascha Brawer
-->

# production

Infrastructure-as-Code for [brawer.ch](https://brawer.ch) projects. Starting
minimal with Bunny.net S3-compatible storage; more will be added as needed.

## Stack (Phase 1)

| | |
|---|---|
| **Storage** | Bunny.net S3-compatible, DE region (Falkenstein) |
| **IaC** | [OpenTofu](https://opentofu.org/) |
| **State** | Local (`bunny/terraform.tfstate`, gitignored) |
| **Cost** | ~€2–5/month (storage + minimal CDN) |

### Storage zones

Defined in [`bunny/storage.tf`](bunny/storage.tf) as `local.storage_zones`, one
`bunnynet_storage_zone` created per entry via `for_each`:

| Zone | Purpose |
|---|---|
| `brawer-homepage` | Hugo static site |
| `osmdiffs-data` | Project data files (`conflated.pmtiles`, etc.) |
| `osmdiffs-app` | React frontend build |

## Setup

1. Install OpenTofu (`brew install opentofu`).
2. Create an API key at <https://dash.bunny.net/account/settings> and save it,
   with no trailing newline, to `secrets/bunny_api_key`:

   ```sh
   printf %s 'YOUR_API_KEY' > secrets/bunny_api_key
   ```

   The `secrets/` directory is gitignored (except `.gitkeep`).

## Usage

```sh
cd bunny
tofu init      # first time, and after provider bumps
tofu plan
tofu apply
```

### Getting storage credentials

```sh
tofu output s3_endpoints          # per-zone S3 endpoint URLs
tofu output -json s3_credentials  # per-zone "<access-key>:<secret>" (sensitive)
```

For S3-compatible access, the access key ID is the zone name and the secret is
the zone's read-write `password`. Other outputs: `api_endpoints`,
`storage_zone_ids`, `passwords`, `passwords_readonly`.

## Notes

- The local state file contains zone passwords in plaintext — it is gitignored;
  keep it private.
- `.terraform.lock.hcl` is committed to pin provider versions; run
  `tofu init -upgrade` to bump them deliberately.

## License

MIT — see [LICENSE](LICENSE).

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
| `osmdiffs-data` | osmdiffs data files (`conflated.pmtiles`, etc.) |
| `osmdiffs-app` | osmdiffs React frontend build |
| `osmviews-data` | osmviews data files |
| `osmviews-app` | osmviews React frontend build |

Every published object goes under a `data/` prefix in its zone, so the CDN
`/data/*` edge rule (below) always matches.

### CDN & DNS

[`bunny/cdn.tf`](bunny/cdn.tf) defines `local.sites` — one Bunny pull zone per
hostname group, each fronting a storage zone. [`bunny/dns.tf`](bunny/dns.tf)
hosts the domain's DNS on Bunny and links one `PullZone` record per hostname.

`dandelis.ch` (a parked domain) is the guinea pig for the eventual `brawer.ch`
migration and mirrors its planned layout:

The pull zone name is the canonical hostname with dots as dashes, so migrating a
domain to production is a `dandelis` → `brawer` substitution of a copied block.

| Hostname | Pull zone | Origin | Edge rule |
|---|---|---|---|
| `dandelis.ch` | `dandelis-ch` | `brawer-homepage` | — |
| `www.dandelis.ch` | `dandelis-ch` | `brawer-homepage` | 301 → `https://dandelis.ch` |
| `osmviews.dandelis.ch` | `osmviews-dandelis-ch` | `osmviews-app` | `/data/*` → `osmviews-dandelis-ch-data` |
| `osmdiffs.dandelis.ch` | `osmdiffs-dandelis-ch` | `osmdiffs-app` | `/data/*` → `osmdiffs-dandelis-ch-data` |

Each `data_zone` gets a bare pull zone (`…-data`, no custom hostname) fronting
its data storage zone; the `/data/*` edge rule is an `OriginUrl` override to that
pull zone's `b-cdn.net` host, which Bunny fetches with the path appended
(`OriginStorage` is rejected by the API).

Cutover for a domain:

1. `tofu apply` (creates the pull zones, hostnames, edge rules, DNS zone, records).
2. At the registrar, delegate the domain to the nameservers in
   `tofu output dns_nameservers`.
3. Wait for Bunny to issue the managed TLS certificates (dashboard → each pull
   zone → Hostnames → SSL). Then verify over HTTPS.

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

For S3-compatible access: the **access key ID is the zone name** (which is also
the bucket name), the **secret is the zone's read-write `password`**, and the
endpoint is per-region (`https://de-s3.storage.bunnycdn.com`). Bunny supports
**path-style URLs only**. Other outputs: `api_endpoints` (native Storage API
base URLs), `storage_zone_ids`, `passwords`, `passwords_readonly`.

### Uploading files

With the [AWS CLI](https://aws.amazon.com/cli/):

```sh
zone=osmdiffs-data
secret=$(tofu output -json passwords | jq -r ".\"$zone\"")

AWS_ACCESS_KEY_ID=$zone AWS_SECRET_ACCESS_KEY=$secret \
  aws --endpoint-url https://de-s3.storage.bunnycdn.com \
  s3 cp ./conflated.pmtiles "s3://$zone/"
```

With [rclone](https://rclone.org/) (`~/.config/rclone/rclone.conf`):

```ini
[bunny-osmdiffs-data]
type = s3
provider = Other
access_key_id = osmdiffs-data
secret_access_key = <password from `tofu output -json passwords`>
endpoint = https://de-s3.storage.bunnycdn.com
```

```sh
rclone sync ./public bunny-osmdiffs-data:osmdiffs-data
```

Or the native Storage API (no S3 client needed):

```sh
zone=brawer-homepage
curl -T ./index.html -H "AccessKey: $(tofu output -json passwords | jq -r ".\"$zone\"")" \
  "$(tofu output -json api_endpoints | jq -r ".\"$zone\"")index.html"
```

## Notes

- The local state file contains zone passwords in plaintext — it is gitignored;
  keep it private.
- `.terraform.lock.hcl` is committed to pin provider versions; run
  `tofu init -upgrade` to bump them deliberately.

## License

MIT — see [LICENSE](LICENSE).

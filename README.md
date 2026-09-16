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
| **Cost** | ~€2–5/month (storage + minimal CDN); capped — see [Cost guard rails](#cost-guard-rails) |

### Storage zones

Defined in [`bunny/storage.tf`](bunny/storage.tf) as `local.storage_zones`, one
`bunnynet_storage_zone` created per entry via `for_each`:

| Zone | Purpose |
|---|---|
| `brawer-homepage` | Hugo static site |
| `osmdiffs-data-de` | osmdiffs data files (`conflated.pmtiles`, etc.); `type = "S3"` |
| `osmdiffs-app` | osmdiffs React frontend build |
| `osmviews-data-de` | osmviews data files; `type = "S3"` |
| `osmviews-app` | osmviews React frontend build |

Every published object goes under a `data/` prefix in its zone, so the CDN
`/data/*` edge rule (below) always matches.

### CDN & DNS

[`bunny/cdn.tf`](bunny/cdn.tf) defines `local.sites` — one Bunny pull zone per
hostname group, each fronting a storage zone. [`bunny/dns.tf`](bunny/dns.tf)
hosts the domain's DNS on Bunny and links one `PullZone` record per hostname.

`dandelis.ch` was the guinea pig for the `brawer.ch` migration and has since
been decommissioned (2026-09-14) — parked, no Bunny DNS, no website, no mail —
now that `brawer.ch` is the real live domain:

The pull zone name is the canonical hostname with dots as dashes
(`brawer.ch` → `brawer-ch`).

| Hostname | Pull zone | Origin | Edge rule | Cutover |
|---|---|---|---|---|
| `brawer.ch` | `brawer-ch` | `brawer-homepage` | — | live |
| `www.brawer.ch` | `brawer-ch` | `brawer-homepage` | 301 → `https://brawer.ch` | live |
| `osmviews.brawer.ch` | `osmviews-brawer-ch` | `osmviews-app` | `/data/*` → `osmviews-brawer-ch-data` | live |
| `osmdiffs.brawer.ch` | `osmdiffs-brawer-ch` | `osmdiffs-app` | `/data/*` → `osmdiffs-brawer-ch-data` | live |

`brawer.ch`'s registrar transferred to Infomaniak and its nameservers delegate
to Bunny (`kiki`/`coco.bunny.net`, verified 2026-09-14), so `cutover` is `true`
— Bunny issues managed TLS certificates once a pull zone hostname's DNS
actually resolves to it. `dns.tf` also hosts Infomaniak mail records
(MX/SPF/autoconfig/autodiscover/DKIM) for it. See
[issue #6](https://github.com/brawer/production/issues/6).

Each `data_zone` gets a bare pull zone (`…-data`, no custom hostname) fronting
its data storage zone; the `/data/*` edge rule is an `OriginUrl` override to that
pull zone's `b-cdn.net` host, which Bunny fetches with the path appended
(`OriginStorage` is rejected by the API).

### Caching

Storage origins send no `Cache-Control`, so each site pull zone pins an explicit
**300 s** edge + browser TTL (with stale-while-revalidate). A deploy is then
visible within minutes without a cache purge — which is deliberate: the deploy
pipelines are never given the Bunny account API key (it can't be scoped), and it
is the only credential that can purge.

Content-hashed assets get a longer TTL (`local.immutable_max_age`) via a per-site
`immutable_assets` edge rule. The URL globs it matches depend on the site's
`kind`:

| `kind` | Matched as content-hashed |
|---|---|
| `hugo` | `*.min.*.css`, `*.min.*.js`, `*_hu*` images, `/fonts/*` |
| `spa` | `/assets/*` |

`immutable_max_age` starts at **600 s** — deliberately short until a real deploy
has proven the globs match only hashed files and the build actually fingerprints.
A follow-up then bumps it to 30 days ([issue #13](https://github.com/brawer/production/issues/13)).

**`/data/*`** (the projects' download CDN — see
[brawer/osmviews#110](https://github.com/brawer/osmviews/issues/110)) has its own
split, on the site zone so it reaches the client through the `OriginUrl` hop:
`datapackage.json` is overwritten in place each build, so it gets
`local.data_manifest_max_age` (**60 s**, `data_manifest` rule); every other
`/data/` object is immutable by its dated URL (`osmviews-<date>.tiff`,
`*.pmtiles`, `*.parquet`, `*.cdx.json`, …) and gets `local.immutable_max_age`
(`data_immutable` rule, a negative match so new file types need no change). The
inner `…-data` pull zone is also pinned to 60 s so an overwritten manifest can't
sit stale in that tier.

`spa` sites will also need a `404 → /index.html` history-fallback edge rule once
a frontend actually exists (`TODO` in `cdn.tf`). The Hugo build side is
[brawer/homepage#81](https://github.com/brawer/homepage/issues/81).

### Cost guard rails

A hobby account should not be able to produce a surprise four-figure bill. Two
layers:

1. **Per-pull-zone monthly egress caps** — `limit_bandwidth` in `cdn.tf`
   (`local.sites[*].bandwidth_cap_gib`, `local.sites[*].data_bandwidth_cap_gib`). Bunny
   disables a zone once it serves that much in a calendar month, then re-enables
   it at the boundary. Stops one hammered zone from draining the whole balance;
   raise the number here or in the dashboard to lift a stop.
2. **Prepaid balance, auto-recharge OFF** — the absolute ceiling. Bunny never
   charges a card without auto-recharge and suspends zones on a negative
   balance, so exposure ≈ whatever is topped up. Keep it around €50; Bunny
   emails a warning as the balance falls, and the dashboard shows
   month-to-date charges.

No automated spend alert: it would need the un-scopeable account API key in a
scheduled job, which is not worth it once the caps bound the downside.

Global edge coverage is kept for every zone (small HTML + content-hashed
bundles); serving only `/data/*` from the cheaper EU + North America regions
would need those files on their own hostname — see
[issue #10](https://github.com/brawer/production/issues/10).

For a manual purge (e.g. after correcting a page), from a machine that has
`secrets/bunny_api_key`:

```sh
curl -X POST -H "AccessKey: $(cat secrets/bunny_api_key)" \
  "https://api.bunny.net/pullzone/$(cd bunny && tofu output -json pullzone_ids | jq '."brawer.ch"')/purgeCache"
```

Cutover for a domain:

1. `tofu apply` with `cutover = false` for the domain in `local.sites`
   (creates the pull zones, hostnames, edge rules, DNS zone, records — no
   effect on the live domain, which is still delegated elsewhere).
2. At the registrar, delegate the domain to the nameservers in
   `tofu output dns_nameservers` (a map keyed by domain). Verify with
   `dig NS <domain>` before the next step — don't trust it secondhand.
3. Flip `cutover = true` for the domain and `tofu apply` again; Bunny then
   attempts managed TLS certificate issuance. If a hostname fails with
   `loadFreeCertificate failed` / `"not pointing to our servers"`, that's a
   known race — just re-run `tofu apply`, no config change needed. Then
   verify over HTTPS.

`brawer.ch` completed this and is live (registrar transferred to Infomaniak,
NS delegated to Bunny, 2026-09-14) — see
[issue #6](https://github.com/brawer/production/issues/6). `dandelis.ch`, the
domain that proved out this checklist, has since been decommissioned.

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

The S3 API only works on zones created with `type = "S3"` (see
[`storage.tf`](bunny/storage.tf)) — currently the `-data` zones. `Standard`
zones (`-app`, homepage) expose only the native Storage API (`api_endpoints`).

### Uploading files

With the [AWS CLI](https://aws.amazon.com/cli/):

```sh
zone=osmdiffs-data-de
secret=$(tofu output -json passwords | jq -r ".\"$zone\"")

AWS_ACCESS_KEY_ID=$zone AWS_SECRET_ACCESS_KEY=$secret \
  aws --endpoint-url https://de-s3.storage.bunnycdn.com \
  s3 cp ./conflated.pmtiles "s3://$zone/"
```

With [rclone](https://rclone.org/) (`~/.config/rclone/rclone.conf`):

```ini
[bunny-osmdiffs-data-de]
type = s3
provider = Other
access_key_id = osmdiffs-data-de
secret_access_key = <password from `tofu output -json passwords`>
endpoint = https://de-s3.storage.bunnycdn.com
```

```sh
rclone sync ./public bunny-osmdiffs-data-de:osmdiffs-data-de
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

## Infomaniak

**`infomaniak/` and `infomaniak-k8s/` are currently disabled** — every
resource in both is commented out (search either directory for "DISABLED"),
so `tofu apply` there is a guaranteed no-op rather than silently recreating
a real, billed Kubernetes cluster. They were torn down after a successful
validation run; `infomaniak-s3-auth/` and `infomaniak-storage/` are
unaffected and stay live. To use the cluster again, uncomment both
modules' `.tf` files and follow Usage below.

Four more OpenTofu root modules — `infomaniak/`, `infomaniak-k8s/`,
`infomaniak-s3-auth/`, and `infomaniak-storage/` — each with its own local
state and its own credentials (three different Infomaniak auth mechanisms;
see each module's Setup below). Two module boundaries here aren't just file
organization but work around the same constraint: a provider can't be
configured from a value that's only known after that same apply creates the
resource it comes from. `infomaniak-k8s/` reads its kubeconfig back from
`infomaniak/`'s already-applied state via `terraform_remote_state`, and
`infomaniak-storage/` reads its S3 credential back from
`infomaniak-s3-auth/`'s the same way.

| | |
|---|---|
| **`infomaniak/`** | Managed Kubernetes (KaaS) cluster, via the [Infomaniak provider](https://registry.terraform.io/providers/Infomaniak/infomaniak/latest) |
| **`infomaniak-k8s/`** | The CronJob workload on that cluster, via `hashicorp/kubernetes` |
| **`infomaniak-s3-auth/`** | An OpenStack EC2 credential (S3 access/secret keys) for the project, via `terraform-provider-openstack/openstack` |
| **`infomaniak-storage/`** | S3-compatible Object Storage buckets, via `hashicorp/aws` pointed at a custom endpoint, using that credential |
| **State** | Local (`<module>/terraform.tfstate`, all gitignored) |
| **Cost** | KaaS control plane free (`pack_name = "shared"`); worker node(s) billed only while running (`min_instances = 0`, scale-to-zero, ~$0.04/h when up); Object Storage billed per GB stored/transferred |

Domain registrar transfer (brawer.ch: itfactory.ag → Infomaniak, completed
2026-09-14) was a manual, one-time step outside OpenTofu — Infomaniak's
provider only manages DNS zones/records (`infomaniak_zone`/`infomaniak_record`)
and cloud resources (KaaS, DBaaS), not registrar transfers. Nothing here
depended on it: DNS hosting stays on Bunny (`bunny/dns.tf`) regardless of
which registrar holds the domain.

### KaaS cluster (`infomaniak/kaas.tf`)

One cluster (`infomaniak_kaas.cronjobs`) and one autoscaling node pool
(`infomaniak_kaas_instance_pool.cronjobs`), scaled to zero when idle — the
cronjob it exists for (below) runs ~4h once a week, so a fixed always-on node
would sit idle >99% of the time. Lives inside an existing Infomaniak Public
Cloud project (`public_cloud_id`/`public_cloud_project_id`, no Terraform
resource creates the project itself — a one-time manual step, Manager →
Public Cloud → create project). `region`, `kubernetes_version`,
`flavor_name`, and `availability_zone` are all verified against the real API
(`GET /1/public_clouds/kaas/{regions,versions,availability_zones}` and the
project's `.../kaas/flavors`) rather than guessed — see the comments in
`kaas.tf` for the exact calls, useful again if any of these need to change.

**Unverified, check on the first apply:** whether Infomaniak's autoscaler
actually supports scaling from zero, and whether the cluster's kubeconfig has
the client-certificate shape `infomaniak-k8s/main.tf` assumes (swap in a
bearer `token` there if not).

### CronJob workload (`infomaniak-k8s/cronjob.tf`)

A weekly `kubernetes_cron_job_v1`: 8 vCPUs / 8 GiB RAM, a 200 GiB ephemeral
scratch volume (`volume.ephemeral`, so it's created fresh per run and never
lingers between weeks), and S3 credentials injected via a
`kubernetes_secret_v1` (`env_from`). TODO before the first apply: replace the
`busybox` placeholder image/command with the real job, create
`secrets/infomaniak_cronjob_s3_credentials.json` (gitignored — see the
comment in `cronjob.tf` for its shape) with the real credentials, and verify
`storage_class_name` against `kubectl get storageclass` once the cluster
exists.

### S3 credential (`infomaniak-s3-auth/main.tf`)

Object Storage isn't reachable through the Infomaniak account API at all —
only through the OpenStack API for the Public Cloud project, using OpenStack
EC2-style access/secret keys, not the account token. Rather than the manual
"download `clouds.yaml`, run `openstack ec2 credentials create`" flow
Infomaniak's own docs describe, this module gets there entirely via the
account API and Terraform:

- Connection details (`auth_url`, project ID, username, domains, region) —
  fetched once via `GET .../users/{id}/openrc` (an async job; see the
  comments in `main.tf` for the exact calls) instead of a downloaded
  `clouds.yaml`.
- A password for the project's OpenStack user — this project's user had
  none, so one was set once via `PATCH .../users/{id}` (the one manual,
  non-Terraform-managed bootstrap step here, parallel to the Public Cloud
  project itself needing to exist first for `infomaniak/`). Stored in
  `secrets/infomaniak_openstack_password`; rotating it means re-running that
  `PATCH` with the new value.
- The actual EC2 credential — `openstack_identity_ec2_credential_v3`, a real
  Terraform resource that does exactly what `openstack ec2 credentials
  create` does.

**Unverified / worth knowing:** the AWS provider's default (virtual-hosted-
style S3 addressing) fails against Infomaniak's Swift-S3 layer with
`InvalidBucketName` on `CreateBucket` — `infomaniak-storage/`'s
`s3_use_path_style = true` is required, not cosmetic; removing it breaks bucket
creation (confirmed by reproducing the failure with `TF_LOG=DEBUG`).

### Object Storage (`infomaniak-storage/buckets.tf`)

Internal-only S3 buckets (logs, inter-run caches for scheduled jobs — not for
public downloads, that's Bunny's `/data/*` CDN). Infomaniak Public Cloud
Object Storage is Swift with an S3-compatible layer on top and has no
dedicated Infomaniak Terraform resource, so this module talks to it like any
other S3-compatible service: `hashicorp/aws` pointed at
`https://s3.pub1.infomaniak.cloud`, path-style addressing (see above),
`region` a pure compatibility placeholder (data stays in Infomaniak's Swiss
DCs regardless), credentials from `infomaniak-s3-auth/`. Buckets are private
by default (nothing here sets a public-read policy); `local.buckets`
currently has one entry, **`osmdiffs-internal`** (live, created 2026-09-14),
for the weekly cronjob above.

### Setup

1. Create an Infomaniak account API token (used by `infomaniak/`'s
   `infomaniak_kaas` resources and `infomaniak-s3-auth/`'s OpenRC/password
   calls) at
   <https://www.infomaniak.com/en/support/faq/2582/generate-and-manage-infomaniak-api-tokens>
   — Public Cloud read+write scope covers everything here — and save it,
   with no trailing newline, to `secrets/infomaniak_api_token`.
2. Bootstrap `infomaniak-s3-auth/`'s OpenStack password (one-time, see that
   module's comments for the exact `PATCH` call) and save it to
   `secrets/infomaniak_openstack_password`.
3. Create `secrets/infomaniak_cronjob_s3_credentials.json` (see
   `infomaniak-k8s/cronjob.tf`) and replace `cronjob.tf`'s placeholder
   image/command with the real job.

### Usage

Apply in dependency order — each of these reads the previous one's state via
`terraform_remote_state`:

```sh
cd infomaniak && tofu init && tofu apply
cd ../infomaniak-k8s && tofu init && tofu apply

cd ../infomaniak-s3-auth && tofu init && tofu apply
cd ../infomaniak-storage && tofu init && tofu apply
```

(The two pairs are independent of each other — different providers, different
credentials.)

For your own manual access (`aws`/`s3cmd` from a workstation, not through
Terraform), get the credential values with:

```sh
cd infomaniak-s3-auth
tofu output -raw access
tofu output -raw secret
```

and point your client at the endpoint from `infomaniak-storage`'s
`s3_endpoint` output, with **path-style addressing** — same requirement as
the Terraform provider above. For the AWS CLI, a named profile
(`~/.aws/config`) — verified working end-to-end (`cp`/`ls`/`rm`) with
**both** settings below; each was a real, reproduced failure without it:

```ini
[profile infomaniak]
region = us-east-1
endpoint_url = https://s3.pub1.infomaniak.cloud
# NOT nested under `s3 =` below - that block is only for other S3 settings
# (addressing_style etc.); a nested endpoint_url there is silently ignored
# and every request goes to real AWS instead, failing with
# InvalidAccessKeyId (since our key isn't a real AWS key).
request_checksum_calculation = when_required
response_checksum_validation = when_required
# Without the two checksum settings above, `s3 cp` uploads fail with
# "NotImplemented: Transfering payloads in multiple chunks using
# aws-chunked is not supported" - the CLI's default streaming-checksum
# upload encoding, which Infomaniak's Swift-S3 layer doesn't implement.
s3 =
    addressing_style = path
```

then `aws --profile infomaniak s3 ls s3://osmdiffs-internal`. For `s3cmd`
(`brew install s3cmd`), a separate config file (e.g. `~/.s3cfg-infomaniak`,
so it doesn't touch any default `~/.s3cfg`) — also verified end-to-end
(`put`/`ls`/`get`/`del`):

```ini
[default]
access_key = <from tofu output>
secret_key = <from tofu output>
host_base = s3.pub1.infomaniak.cloud
host_bucket = s3.pub1.infomaniak.cloud/%(bucket)s
use_https = True
signature_v2 = True
```

`signature_v2 = True` (not `False`): SigV4 gave `403 SignatureDoesNotMatch`
on any bucket-scoped request (bare `s3cmd ls` with no bucket worked either
way) - a known rough edge for `s3cmd` against non-AWS S3-compatible
backends. Then `s3cmd -c ~/.s3cfg-infomaniak ls s3://osmdiffs-internal`.

## License

MIT — see [LICENSE](LICENSE).

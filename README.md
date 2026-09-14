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

`dandelis.ch` (a parked domain) was the guinea pig for the `brawer.ch`
migration; both now sit side by side in `local.sites`, pointing at the same
origin storage zones (they're domain-independent):

The pull zone name is the canonical hostname with dots as dashes, so each
`brawer.ch` entry is a `dandelis` → `brawer` substitution of the matching
`dandelis.ch` block, plus a per-site `cutover` flag (see `cdn.tf`).

| Hostname | Pull zone | Origin | Edge rule | Cutover |
|---|---|---|---|---|
| `dandelis.ch` | `dandelis-ch` | `brawer-homepage` | — | live |
| `www.dandelis.ch` | `dandelis-ch` | `brawer-homepage` | 301 → `https://dandelis.ch` | live |
| `osmviews.dandelis.ch` | `osmviews-dandelis-ch` | `osmviews-app` | `/data/*` → `osmviews-dandelis-ch-data` | live |
| `osmdiffs.dandelis.ch` | `osmdiffs-dandelis-ch` | `osmdiffs-app` | `/data/*` → `osmdiffs-dandelis-ch-data` | live |
| `brawer.ch` | `brawer-ch` | `brawer-homepage` | — | staged |
| `www.brawer.ch` | `brawer-ch` | `brawer-homepage` | 301 → `https://brawer.ch` | staged |
| `osmviews.brawer.ch` | `osmviews-brawer-ch` | `osmviews-app` | `/data/*` → `osmviews-brawer-ch-data` | staged |
| `osmdiffs.brawer.ch` | `osmdiffs-brawer-ch` | `osmdiffs-app` | `/data/*` → `osmdiffs-brawer-ch-data` | staged |

"Staged" means the Bunny DNS zone, pull zones, and DNS records all exist, but
the registrar still points `brawer.ch` at its old host (Hostpoint) and the
pull zone hostnames stay `tls_enabled = false` (managed-cert issuance would
fail while the hostname still resolves elsewhere). Flipping `cutover = true`
in `cdn.tf` after the registrar nameserver change issues the certs. `dns.tf`
also stages Infomaniak mail records (MX/SPF/autoconfig/autodiscover/DKIM) for
`brawer.ch`, identical in shape to `dandelis.ch`'s. See
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
  "https://api.bunny.net/pullzone/$(cd bunny && tofu output -json pullzone_ids | jq '."dandelis.ch"')/purgeCache"
```

Cutover for a domain:

1. `tofu apply` with `cutover = false` for the domain in `local.sites`
   (creates the pull zones, hostnames, edge rules, DNS zone, records — no
   effect on the live domain, which is still delegated elsewhere).
2. At the registrar, delegate the domain to the nameservers in
   `tofu output dns_nameservers` (a map keyed by domain).
3. Flip `cutover = true` for the domain and `tofu apply` again; Bunny then
   attempts managed TLS certificate issuance (dashboard → each pull zone →
   Hostnames → SSL). Then verify over HTTPS.

`brawer.ch` is staged this way (step 1 done — see the table above); step 2
(the registrar nameserver change) is deferred until `dandelis.ch` has proven
itself in daily use and real content is in all three storage zones — see
[issue #6](https://github.com/brawer/production/issues/6) for the checklist.

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

Two more OpenTofu root modules — `infomaniak/` and `infomaniak-k8s/`, each
with its own local state. They're separate modules (not just separate files)
because configuring the `kubernetes` provider from a cluster's own kubeconfig
output in the same apply that creates the cluster is unreliable (provider
config can't depend on a value that's unknown until that apply's resources
are actually created); `infomaniak-k8s/` instead reads the kubeconfig back
from `infomaniak/`'s already-applied state via `terraform_remote_state`.

| | |
|---|---|
| **`infomaniak/`** | Managed Kubernetes (KaaS) cluster, via the [Infomaniak provider](https://registry.terraform.io/providers/Infomaniak/infomaniak/latest) |
| **`infomaniak-k8s/`** | The CronJob workload on that cluster, via `hashicorp/kubernetes` |
| **State** | Local (`infomaniak/terraform.tfstate`, `infomaniak-k8s/terraform.tfstate`, both gitignored) |
| **Cost** | Control plane free (`pack_name = "shared"`); worker node(s) billed only while running (`min_instances = 0`, scale-to-zero) |

Domain registrar transfer (brawer.ch, dandelis.ch: itfactory.ag → Infomaniak)
is a manual, one-time step outside OpenTofu — Infomaniak's provider only
manages DNS zones/records (`infomaniak_zone`/`infomaniak_record`) and cloud
resources (KaaS, DBaaS), not registrar transfers. Nothing here depends on it:
DNS hosting stays on Bunny (`bunny/dns.tf`) regardless of which registrar
holds the domain.

### KaaS cluster (`infomaniak/kaas.tf`)

One cluster (`infomaniak_kaas.cronjobs`) and one autoscaling node pool
(`infomaniak_kaas_instance_pool.cronjobs`), scaled to zero when idle — the
cronjob it exists for (below) runs ~4h once a week, so a fixed always-on node
would sit idle >99% of the time.

The cluster lives inside an existing Infomaniak Public Cloud project; the
provider has no resource to create that project itself (Manager → Public
Cloud → create project is a one-time manual step first). Several values in
`kaas.tf` are marked `TODO` and must be filled in from your own project
before the first apply — `public_cloud_id`, `public_cloud_project_id`,
`region`, `flavor_name`, `availability_zone` — see the comments there for the
exact discovery commands.

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

### Setup

1. Create an API token at
   <https://www.infomaniak.com/en/support/faq/2582/generate-and-manage-infomaniak-api-tokens>
   and save it, with no trailing newline, to `secrets/infomaniak_api_token`.
2. Fill in the `TODO`s in `infomaniak/kaas.tf` (see above).
3. Create `secrets/infomaniak_cronjob_s3_credentials.json` (see
   `infomaniak-k8s/cronjob.tf`) and replace `cronjob.tf`'s placeholder
   image/command with the real job.

### Usage

Apply the cluster before the workload — `infomaniak-k8s/` reads the
kubeconfig back from `infomaniak/`'s state, so it needs that state to exist:

```sh
cd infomaniak && tofu init && tofu apply
cd ../infomaniak-k8s && tofu init && tofu apply
```

## License

MIT — see [LICENSE](LICENSE).

# Revisions and traffic splitting

## Single vs multiple revision mode

| Mode | Behaviour | Use for |
|------|-----------|---------|
| `single` (default) | Each new revision replaces the previous one automatically, with zero downtime | Simple apps, every deploy goes straight to production |
| `multiple` | Several revisions stay active and you decide how traffic is split | Blue/green, canary, A/B testing |

This lab creates the app with `--revisions-mode multiple`. To change an existing app:

```bash
az containerapp revision set-mode -n website -g rg-aca-lab --mode multiple
```

## What creates a new revision?

| Change | New revision? |
|--------|---------------|
| Template: image, env vars, CPU/memory, probes, min/max replicas, scale rules (`az containerapp update`) | **Yes**, named `<app>--<revision-suffix>` |
| Configuration: ingress, traffic weights, registries, secrets, identity | No |

A revision suffix can only be used **once** per app. Use a new tag (or suffix) for every release.

## "Latest revision" vs pinned traffic

By default, ingress sends traffic to the **latest revision** (`latestRevision: true`). Every update goes live immediately.

Step 3 pins traffic to a named revision instead:

```bash
az containerapp ingress traffic set -n website -g rg-aca-lab --revision-weight website--v1=100
```

From then on, new revisions start with **0%** traffic until you move it. To go back to "always follow the latest":

```bash
az containerapp ingress traffic set -n website -g rg-aca-lab --revision-weight latest=100
```

## Labels

A label is a stable name attached to one revision, with its own URL:

```
https://<app>---<label>.<environment default domain>
```

```bash
az containerapp revision label add    -n website -g rg-aca-lab --label green --revision website--v2
az containerapp revision label swap   -n website -g rg-aca-lab --source blue --target green
az containerapp revision label remove -n website -g rg-aca-lab --label green
```

Labels can also take traffic weights, which lets a pipeline say "send 10% to *green*" without knowing the revision name:

```bash
az containerapp ingress traffic set -n website -g rg-aca-lab --label-weight blue=90 green=10
```

## A typical release

```
1. build image v2                   az acr build ... --image website:v2
2. create revision, 0% traffic      az containerapp update --image ...:v2 --revision-suffix v2
3. test on the label URL            https://website---green.<domain>
4. canary                           --revision-weight website--v2=10 website--v1=90
5. watch errors / latency           az containerapp logs show, Metrics blade
6. cut over                         --revision-weight website--v2=100
7. keep v1 for quick rollback, then deactivate it
```

## Useful commands

```bash
az containerapp revision list -n website -g rg-aca-lab -o table \
  --query "[].{name:name, active:properties.active, traffic:properties.trafficWeight, replicas:properties.replicas, created:properties.createdTime}"
az containerapp revision show       -n website -g rg-aca-lab --revision website--v2
az containerapp revision restart    -n website -g rg-aca-lab --revision website--v2
az containerapp revision deactivate -n website -g rg-aca-lab --revision website--v1
az containerapp revision activate   -n website -g rg-aca-lab --revision website--v1
```

Notes:

- An inactive revision cannot receive traffic. Activate it before rolling back to it.
- Inactive revisions are kept (up to 100), so old ones can be reactivated later.

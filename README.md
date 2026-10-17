# Azure Container Apps Lab with the Azure CLI: Website from ACR to Container Apps

A hands-on lab that builds a containerized website, stores it in **Azure Container Registry (ACR)**, and runs it on **Azure Container Apps** with HTTPS, autoscaling (including scale to zero), and blue/green releases using **revisions and traffic splitting**.

Everything is done with the **Azure CLI** (`az`), one small script per step, so you can read each command before you run it.

```
  your laptop / Cloud Shell
          │  az acr build (the image is built in Azure, no local Docker needed)
          ▼
 ┌──────────────────────────┐        AcrPull         ┌─────────────────────────────┐
 │ Azure Container Registry │ ◄───────────────────── │ user-assigned managed       │
 │   website:v1, v2, v3     │                        │ identity (no passwords)     │
 └──────────────────────────┘                        └──────────────┬──────────────┘
                                                                    │ used by
 ┌──────────────────────────────────────────────────────────────────▼──────────────┐
 │ Container Apps environment (logs → Log Analytics)                                │
 │                                                                                  │
 │   container app "website"   ingress: external HTTPS → port 8080                  │
 │     ├── revision website--v1   80% ──┐                                           │
 │     └── revision website--v2   20% ──┤  ◄── https://website.<env-domain>         │
 │            label "green" ────────────┼───── https://website---green.<env-domain> │
 │   scale: 0 to 5 replicas, HTTP rule (20 concurrent requests per replica)         │
 └──────────────────────────────────────────────────────────────────────────────────┘
```

## What you will learn

- Create a private **Azure Container Registry** and build images in the cloud with **ACR Tasks** (`az acr build`)
- Let an app pull images with a **managed identity** and the **AcrPull** role instead of registry passwords
- Create a **Container Apps environment** wired to **Log Analytics**
- Deploy a **container app** with external HTTPS ingress, CPU/memory limits, and an **HTTP scale rule**
- Watch **scale to zero** and cold starts
- Release new versions as **revisions**, test them on a **label URL**, then shift traffic gradually (canary) and roll back instantly
- Read container logs with `az containerapp logs show` and Log Analytics queries
- Clean up everything with one command

## Project structure

```
azure-container-apps-cli-lab/
├── app/
│   ├── Dockerfile          # nginx (unprivileged, port 8080), version/color baked in at build time
│   ├── nginx.conf          # /health and /version.json endpoints
│   ├── index.html          # the website
│   └── .dockerignore
├── scripts/
│   ├── config.sh               # shared settings (names, region) + helpers
│   ├── 01-create-foundation.sh # resource group, Log Analytics, ACR, managed identity + AcrPull
│   ├── 02-build-image.sh       # az acr build → website:<tag>
│   ├── 03-create-app.sh        # Container Apps environment + the website app (revision v1)
│   ├── 04-release.sh           # new revision with 0% traffic + "green" test label
│   ├── 05-shift-traffic.sh     # canary / cut over / roll back
│   ├── 06-watch-versions.sh    # count which version answers
│   ├── 07-load-test.sh         # watch the scale rule add replicas
│   └── 99-cleanup.sh           # delete the resource group
└── docs/
    ├── concepts.md             # Container Apps vs AKS vs App Service, how it fits together
    ├── revisions-and-traffic.md
    └── troubleshooting.md
```

## Prerequisites

| Tool | Notes |
|------|-------|
| Azure subscription | A free account works. You need **Owner** or **User Access Administrator** on the subscription (or resource group) to create the AcrPull role assignment. |
| Azure CLI 2.62+ | `az version`. Or use **Azure Cloud Shell** (Bash), which has everything installed. |
| bash, curl, python3 | For the helper scripts. Already in Cloud Shell. |
| Docker | **Optional.** Only for `02-build-image.sh ... --local` and for running the site locally. |

```bash
az login
az account set --subscription "<your subscription name or id>"
az extension add --name containerapp --upgrade   # newest Container Apps commands
```

## Quick start

```bash
git clone https://github.com/KwakuAdae/azure-container-apps-cli-lab.git
cd azure-container-apps-cli-lab

./scripts/01-create-foundation.sh      # ~2 min
./scripts/02-build-image.sh v1 blue    # ~1 min
./scripts/03-create-app.sh v1          # ~3 min, prints your https URL
```

Open the printed URL. When you are finished: `./scripts/99-cleanup.sh`.

---

## Step-by-step guide

### Step 0: (Optional) Run the website locally

```bash
docker build -t website:local --build-arg APP_VERSION=local --build-arg APP_COLOR=orange app/
docker run --rm -p 8080:8080 website:local
# http://localhost:8080   http://localhost:8080/health   http://localhost:8080/version.json
```

The image is `nginx-unprivileged`, listens on **8080**, and runs as a non-root user. The build args `APP_VERSION` and `APP_COLOR` are baked into the page so you can see which version served each request.

### Step 1: Create the foundation

```bash
./scripts/01-create-foundation.sh
```

What it does:

1. Registers the resource providers `Microsoft.App`, `Microsoft.OperationalInsights`, `Microsoft.ContainerRegistry` and `Microsoft.ManagedIdentity` (one time per subscription).
2. Creates the resource group `rg-aca-lab` in `eastus`. Change the region with `export LOCATION=westeurope` before running.
3. Creates a **Log Analytics workspace**. The Container Apps environment sends container stdout/stderr and system logs here.
4. Creates an **Azure Container Registry** on the **Basic** SKU with the **admin user disabled**. The name must be globally unique, so the script generates one (e.g. `acracalab7k2m9q`) and saves it in `.lab-env` for the next steps.
5. Creates a **user-assigned managed identity** and gives it the **AcrPull** role on the registry.

The key commands:

```bash
az acr create -g rg-aca-lab -n <acr-name> --sku Basic --admin-enabled false
az identity create -g rg-aca-lab -n id-aca-lab-acrpull
az role assignment create --assignee-object-id <principalId> \
  --assignee-principal-type ServicePrincipal --role AcrPull --scope <acr-id>
```

Why a user-assigned identity? It exists *before* the app does, so the role assignment is already in place when the app pulls its first image. With a system-assigned identity you would hit a chicken-and-egg problem on the first deployment.

Check it:

```bash
source .lab-env
az acr show -n "$ACR_NAME" --query "{server:loginServer, sku:sku.name, admin:adminUserEnabled}" -o table
az role assignment list --scope "$(az acr show -n "$ACR_NAME" --query id -o tsv)" -o table
```

### Step 2: Build and push the image with ACR Tasks

```bash
./scripts/02-build-image.sh v1 blue
```

```bash
az acr build --registry <acr-name> --image website:v1 --platform linux/amd64 \
  --build-arg APP_VERSION=v1 --build-arg APP_COLOR=blue app/
```

`az acr build` uploads the `app/` folder (respecting `.dockerignore`), builds it **inside Azure** for `linux/amd64`, and pushes `website:v1` to your registry. You do not need Docker on your machine, and the build works the same from an Apple Silicon Mac.

Build the versions you will release later now, so they are ready:

```bash
./scripts/02-build-image.sh v2 green
./scripts/02-build-image.sh v3 orange
```

> Prefer your own Docker? `./scripts/02-build-image.sh v1 blue --local` runs `az acr login`, `docker build` and `docker push` instead.

### Step 3: Create the environment and the container app

```bash
./scripts/03-create-app.sh v1
```

1. **Container Apps environment** (`cae-aca-lab`): the secure boundary that apps share. It provides the networking, the default domain, and the log destination (your Log Analytics workspace).

   ```bash
   az containerapp env create -n cae-aca-lab -g rg-aca-lab \
     --logs-destination log-analytics --logs-workspace-id <id> --logs-workspace-key <key>
   ```

2. **Container app** (`website`):

   ```bash
   az containerapp create -n website -g rg-aca-lab --environment cae-aca-lab \
     --image <acr>.azurecr.io/website:v1 \
     --user-assigned <identity-id> \
     --registry-server <acr>.azurecr.io --registry-identity <identity-id> \
     --ingress external --target-port 8080 \
     --cpu 0.25 --memory 0.5Gi \
     --min-replicas 0 --max-replicas 5 \
     --scale-rule-name http-concurrency --scale-rule-type http --scale-rule-http-concurrency 20 \
     --revisions-mode multiple --revision-suffix v1
   ```

| Flag | Meaning |
|------|---------|
| `--image` | Image from your private registry |
| `--registry-server` / `--registry-identity` | Pull with the managed identity, no passwords stored |
| `--ingress external --target-port 8080` | Public HTTPS endpoint with a managed TLS certificate, forwarding to port 8080 |
| `--cpu 0.25 --memory 0.5Gi` | Smallest size, plenty for nginx |
| `--min-replicas 0 --max-replicas 5` | **Scale to zero** when idle, up to 5 replicas under load |
| `--scale-rule-type http --scale-rule-http-concurrency 20` | Add a replica for every ~20 concurrent requests |
| `--revisions-mode multiple --revision-suffix v1` | Keep several revisions active at once (needed for blue/green). This revision is named `website--v1` |

3. Pins **100% of traffic to `website--v1`**:

   ```bash
   az containerapp ingress traffic set -n website -g rg-aca-lab --revision-weight website--v1=100
   ```

   Without this, traffic follows the *latest* revision automatically and every update would go live immediately.

Open the printed URL. You should see the blue **v1** page. Try the endpoints:

```bash
source .lab-env
curl -s "$APP_URL/health"
curl -s "$APP_URL/version.json"
az containerapp revision list -n website -g rg-aca-lab -o table
```

### Step 4: Release v2 as a new revision (blue/green)

```bash
./scripts/04-release.sh v2
```

```bash
az containerapp update -n website -g rg-aca-lab --image <acr>.azurecr.io/website:v2 --revision-suffix v2
az containerapp revision label add -n website -g rg-aca-lab --label green --revision website--v2
```

- The update creates revision **`website--v2`**. Because traffic is pinned to v1, v2 receives **0%** of production traffic.
- The **green** label gives v2 its own URL: `https://website---green.<env-domain>` (note the **three** dashes).

Open the **green** URL and you see v2. Open the **production** URL and you still see v1. Both versions are running, and you test the new one before any user sees it.

### Step 5: Shift traffic gradually, then cut over

```bash
./scripts/05-shift-traffic.sh v2 20     # canary: 20% v2, 80% v1
./scripts/06-watch-versions.sh 40
#   ~32 v1 blue
#    ~8 v2 green

./scripts/05-shift-traffic.sh v2 50
./scripts/05-shift-traffic.sh v2 100    # cut over
```

Under the hood it is one command:

```bash
az containerapp ingress traffic set -n website -g rg-aca-lab \
  --revision-weight website--v2=20 website--v1=80
```

**Roll back** at any time, instantly, because v1 is still running:

```bash
./scripts/05-shift-traffic.sh v1 100
```

Repeat the whole flow with v3 (`./scripts/04-release.sh v3`, then shift traffic). When an old revision is no longer needed, deactivate it so it stops using resources:

```bash
az containerapp revision deactivate -n website -g rg-aca-lab --revision website--v1
```

More detail: [docs/revisions-and-traffic.md](docs/revisions-and-traffic.md).

### Step 6: Autoscaling and scale to zero

```bash
./scripts/07-load-test.sh 120 60     # 2 minutes, 60 parallel workers
```

You will see the replica count climb as the HTTP rule reacts to concurrent requests:

```
14:02:10  replicas of website--v2: 1
14:02:25  replicas of website--v2: 3
14:02:40  replicas of website--v2: 5
```

Stop sending traffic and wait about 5 minutes: the replica count drops to **0**. The next request wakes the app (a *cold start* of a few seconds). For a site that must always answer instantly, keep one replica warm:

```bash
az containerapp update -n website -g rg-aca-lab --min-replicas 1 --revision-suffix v2b
```

> Scale settings are part of the revision template, so changing them creates a new revision (`website--v2b` here). Because traffic is pinned, shift traffic to it with `./scripts/05-shift-traffic.sh v2b 100`.

### Step 7: Logs and monitoring

Stream the container's console output (nginx access logs) live:

```bash
az containerapp logs show -n website -g rg-aca-lab --follow --tail 20
az containerapp logs show -n website -g rg-aca-lab --type system   # scaling, image pulls, restarts
```

Query Log Analytics (logs arrive with a delay of a few minutes):

```bash
WS_ID=$(az monitor log-analytics workspace show -g rg-aca-lab -n log-aca-lab --query customerId -o tsv)
az monitor log-analytics query -w "$WS_ID" -o table --analytics-query "
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == 'website'
| summarize requests = count() by RevisionName_s, bin(TimeGenerated, 5m)
| order by TimeGenerated desc"
```

Open a shell inside a running replica (send a request first so one is running):

```bash
az containerapp exec -n website -g rg-aca-lab --command sh
```

In the portal, the app's **Metrics** blade shows *Requests*, *Replica Count* and *CPU Usage* per revision.

### Step 8: Clean up

```bash
./scripts/99-cleanup.sh
```

Everything lives in the resource group `rg-aca-lab`, so deleting it removes the registry, environment, app, identity and workspace.

---

## Cost

| Resource | Approximate cost |
|----------|------------------|
| Container Apps (Consumption plan) | Per second of vCPU and memory while replicas run, plus requests. A monthly **free grant** (180,000 vCPU-seconds, 360,000 GiB-seconds, 2 million requests per subscription) covers this lab. **Scaled to zero = no compute charge.** |
| Azure Container Registry, Basic | About **$0.17 per day** while it exists |
| Log Analytics | Pay per GB ingested. This lab sends a few MB. |
| ACR Tasks builds | Per second of build time, a few cents for this lab |

Running the full lab for an afternoon costs well under $1. Run `./scripts/99-cleanup.sh` when you finish so the registry does not keep charging.

## Troubleshooting (short list)

| Symptom | Fix |
|---------|-----|
| `MissingSubscriptionRegistration` for `Microsoft.App` | Rerun step 1, or `az provider register -n Microsoft.App --wait` |
| App stuck provisioning, system log shows `unauthorized` / image pull failure | The AcrPull role assignment is missing or still propagating. Check with `az role assignment list --scope <acr id>` and wait a minute |
| `AuthorizationFailed` creating the role assignment | You need Owner / User Access Administrator, or ask an admin to grant AcrPull to the identity |
| ACR name already taken | Delete `.lab-env` and rerun step 1 to generate a new registry name |
| "revision with suffix already exists" | Revision suffixes cannot be reused. Build and release a new tag (e.g. `v2b`) |
| First request is slow | Cold start from scale to zero. Expected. Use `--min-replicas 1` to avoid it |
| Green URL returns 404 | Label not set or wrong number of dashes. It is `website---green.` (three) |

More in [docs/troubleshooting.md](docs/troubleshooting.md).

## Going further

- **Custom domain** with a free managed certificate: `az containerapp hostname add` and `az containerapp hostname bind --validation-method CNAME`
- **Secrets and Key Vault references**: `az containerapp secret set` with `keyvaultref:`
- **CI/CD**: `az containerapp github-action add` creates a GitHub Actions workflow that builds to ACR and deploys on every push
- **Infrastructure as code**: see the Terraform version of this lab below
- **Private networking**: create the environment with `--infrastructure-subnet-resource-id` and `--internal-only`
- **Microservices**: add a second app with internal ingress and call it through the environment's service discovery
- **Jobs**: `az containerapp job create` for scheduled or event-driven tasks

## Sister labs

- [azure-container-apps-lab](https://github.com/KwakuAdae/azure-container-apps-lab): this same project with Terraform
- [azure-aks-terraform-lab](https://github.com/KwakuAdae/azure-aks-terraform-lab): the same website on Kubernetes (AKS) with Terraform
- [azure-aks-bicep-lab](https://github.com/KwakuAdae/azure-aks-bicep-lab): AKS with Bicep
- [aws-ecs-fargate-website-lab](https://github.com/KwakuAdae/aws-ecs-fargate-website-lab): the AWS equivalent, ECR + ECS Fargate

## Author

**Kwaku Adae**: [github.com/KwakuAdae](https://github.com/KwakuAdae)

## License

[MIT](LICENSE)

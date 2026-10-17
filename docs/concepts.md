# Concepts

## Where Container Apps fits

| | Azure App Service | **Azure Container Apps** | Azure Kubernetes Service (AKS) |
|---|---|---|---|
| You manage | App settings | Containers, scale rules, revisions | The cluster, node pools, upgrades, add-ons |
| Kubernetes API | No | No (runs on Kubernetes, hidden from you) | Yes, full access |
| Scale to zero | No | **Yes** | Only with extra tooling (KEDA, node autoscaling) |
| Traffic splitting | Deployment slots | **Revisions + weights** | Ingress / service mesh |
| Pricing | Per plan (VMs) | Per second of use (Consumption) or dedicated workload profiles | Per node VM |
| Good for | Web apps and APIs, code or containers | Containerized web apps, APIs, microservices, event-driven jobs | Teams that need Kubernetes itself |

On AWS, the closest service is **ECS on Fargate** (serverless containers) or **App Runner** (the simplest web container hosting).

## The building blocks

**Azure Container Registry (ACR)**
A private Docker registry. `az acr build` (ACR Tasks) builds images inside Azure. The Basic SKU is enough for labs. Standard and Premium add more storage and throughput; Premium adds geo-replication and private endpoints.

**Managed identity + AcrPull**
An identity in Microsoft Entra ID that Azure manages for you. The container app uses it to get a token for the registry, so no username or password is stored anywhere. `AcrPull` is the least-privilege built-in role for pulling images.

**Container Apps environment**
A boundary around a group of apps. Apps in the same environment share a virtual network, a default domain (`<random>.<region>.azurecontainerapps.io`), and a logging destination. Think of it like an ECS cluster or a Kubernetes namespace plus networking.

**Container app**
Your service. It has a configuration (ingress, registries, secrets, revision mode) and a **template** (containers, image, CPU/memory, environment variables, scale rules).

**Revision**
An immutable snapshot of the template. Any change to the template (new image, new env var, new scale setting) creates a new revision named `<app>--<suffix>`. Changes to configuration only (like traffic weights) do not.

**Ingress**
A built-in HTTPS front end (Envoy) with a managed certificate. `external` means reachable from the internet; `internal` means only from inside the environment. It also does the traffic splitting between revisions.

**Scale rules**
Built on KEDA. This lab uses an HTTP rule (concurrent requests per replica). Others: CPU, memory, Azure Service Bus queue length, Event Hubs, and any KEDA scaler. With `min-replicas 0`, an idle app has no running replicas and costs nothing for compute.

## Request flow

```
browser ──HTTPS──► environment ingress (Envoy, TLS)
                       │   weights: website--v1 80%, website--v2 20%
                       ├──► replica of website--v1 :8080 (nginx)
                       └──► replica of website--v2 :8080 (nginx)
```

If the selected revision has 0 replicas, the ingress holds the request while a replica starts (cold start).

## Image pull flow

```
container app ──(managed identity token)──► Microsoft Entra ID
              ──(token, AcrPull)──────────► <acr>.azurecr.io/website:v2
```

## Building blocks as Azure CLI commands

| Concept | Create with | Script |
|---------|-------------|--------|
| Resource group | `az group create` | 01 |
| Log Analytics workspace | `az monitor log-analytics workspace create` | 01 |
| Container registry | `az acr create` | 01 |
| Managed identity | `az identity create` | 01 |
| AcrPull permission | `az role assignment create --role AcrPull` | 01 |
| Image | `az acr build` | 02 |
| Container Apps environment | `az containerapp env create` | 03 |
| Container app (first revision) | `az containerapp create` | 03 |
| New revision | `az containerapp update` | 04 |
| Label | `az containerapp revision label add` | 04 |
| Traffic split | `az containerapp ingress traffic set` | 05 |

Revisions are not created directly: Container Apps creates one whenever the app's template changes.

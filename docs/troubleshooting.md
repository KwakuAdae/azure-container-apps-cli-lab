# Troubleshooting

Start with these three commands. They answer most questions:

```bash
az containerapp revision list -n website -g rg-aca-lab -o table           # running state per revision
az containerapp logs show -n website -g rg-aca-lab --type system --tail 50 # image pulls, probes, scaling
az containerapp logs show -n website -g rg-aca-lab --tail 50               # your container's output
```

## Image pull failures

**Symptom:** the revision stays in `Provisioning` or shows `Failed`. The system log mentions `unauthorized`, `401`, or `manifest unknown`.

| Cause | Check | Fix |
|-------|-------|-----|
| AcrPull missing | `az role assignment list --scope $(az acr show -n $ACR_NAME --query id -o tsv) -o table` | Rerun step 1, or `az role assignment create --assignee-object-id <principalId> --assignee-principal-type ServicePrincipal --role AcrPull --scope <acr id>` |
| Role still propagating | The assignment exists but was created seconds ago | Wait 1 to 2 minutes, then `az containerapp revision restart` |
| Identity not attached to the app | `az containerapp show -n website -g rg-aca-lab --query identity` | `az containerapp identity assign -n website -g rg-aca-lab --user-assigned <identity id>` |
| Registry not configured for the identity | `az containerapp registry list -n website -g rg-aca-lab` | `az containerapp registry set -n website -g rg-aca-lab --server <acr>.azurecr.io --identity <identity id>` |
| Tag does not exist | `az acr repository show-tags -n $ACR_NAME --repository website` | Build it with step 2 |
| Wrong CPU architecture (built on Apple Silicon) | `exec format error` in the logs | Build with `--platform linux/amd64`, or use `az acr build` |

(`source .lab-env` first to get `$ACR_NAME` and the other saved values.)

## App is unreachable

| Symptom | Fix |
|---------|-----|
| 404 from the default domain | Ingress is off or internal: `az containerapp ingress show -n website -g rg-aca-lab` |
| Upstream connect error / 503 | Target port does not match the container. This image listens on **8080**: `az containerapp ingress update -n website -g rg-aca-lab --target-port 8080` |
| Request hangs ~10 seconds, then works | Cold start from zero replicas |
| Label URL fails | Use three dashes: `website---green.<domain>`. Check labels with `az containerapp ingress traffic show` |

## Revision did not get traffic

- Traffic is pinned (step 3). New revisions start at 0%. Use `./scripts/05-shift-traffic.sh`.
- The revision is inactive: `az containerapp revision activate --revision <name>`.
- `--revision-weight` values must add up to 100.

## CLI and subscription errors

| Error | Fix |
|-------|-----|
| `MissingSubscriptionRegistration` | `az provider register -n Microsoft.App --wait` (and the others in step 1) |
| `'containerapp' is misspelled or not recognized` | `az upgrade` or `az extension add -n containerapp --upgrade` |
| `AuthorizationFailed` on role assignment | Your account needs Owner or User Access Administrator |
| Revision suffix already in use | Revision suffixes are single-use. Release a new tag |
| `The subscription has reached its quota` for environments | Delete unused environments or pick another region |
| ACR name `AlreadyInUse` | Names are global. `rm .lab-env` and rerun step 1 |
| `❌ ACR_NAME is not set` from a script | Run step 1 first, from the repo folder (the scripts read `.lab-env`) |

## Logs not showing in Log Analytics

Log Analytics ingestion has a delay of 2 to 5 minutes. For live output use `az containerapp logs show --follow`. Tables:

- `ContainerAppConsoleLogs_CL`: your container's stdout/stderr
- `ContainerAppSystemLogs_CL`: platform events (pulls, scaling, probe failures)

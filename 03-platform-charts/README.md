# petronova-platform-charts

| Chart | Type | Purpose |
|---|---|---|
| `energy-common` | library | Secure defaults for every workload (see its README) |
| `tenant` | application | Namespace onboarding: PSS, quota, LimitRange, RBAC, default-deny |
| `platform-addons/petronova-platform` | application | ClusterSecretStores, Gateway, Cloud Armor attachment, PriorityClasses |
| `platform-addons/external-secrets` | values | Values for the upstream External Secrets Operator chart |
| `platform-addons/gatekeeper` | manifests | Policy Controller constraints (dryrun first) |

Publish (CI does this on merge):

```bash
REG=oci://asia-south1-docker.pkg.dev/pnlab01-prod-shared-artifacts-0/helm-charts
helm package energy-common && helm push energy-common-1.0.0.tgz $REG
helm package tenant && helm push tenant-1.2.0.tgz $REG
```

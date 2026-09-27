# energy-common (library chart)

Owned by the Platform team. Service charts depend on it and only supply values.

| Template | Include | Rendered when |
|---|---|---|
| ServiceAccount (Workload Identity) | `energy-common.serviceaccount` | always |
| Deployment | `energy-common.deployment` | `workload.kind: Deployment` (default) |
| CronJob | `energy-common.cronjob` | `workload.kind: CronJob` |
| Service | `energy-common.service` | `service.enabled` |
| HPA | `energy-common.hpa` | `autoscaling.enabled` |
| PDB | `energy-common.pdb` | `pdb.enabled` |
| NetworkPolicy | `energy-common.networkpolicy` | `networkPolicy.enabled` |
| ConfigMap | `energy-common.configmap` | `config` not empty |
| ExternalSecret | `energy-common.externalsecret` | `externalSecret.enabled` |
| HTTPRoute (Gateway API) | `energy-common.httproute` | `httpRoute.enabled` |
| PodMonitoring (Managed Prometheus) | `energy-common.podmonitoring` | `metrics.enabled` |

Use `{{ include "energy-common.all" . }}` to render everything that applies.
See `values-reference.yaml` for every supported value.

Versioning: SemVer. Breaking value or template changes bump the major version.

# petronova-ci-templates (Platform team)

Reusable GitHub Actions workflows. All auth is keyless (Workload Identity Federation from FAST 0-org-setup).

| Workflow | Used by | Does |
|---|---|---|
| `reusable-terraform.yml` | landing-zone, platform-infra | fmt, validate, plan comment on PR, apply on main |
| `reusable-service-build.yml` | service repos | tests, build, Trivy gate, push, chart release, PR bump in deployments |
| `reusable-chart-release.yml` | chart repos, services | helm lint --strict, kubeconform, package with immutable version, push OCI |
| `reusable-helm-deploy.yml` | petronova-deployments | get-credentials, `scripts/deploy.sh` (atomic + helm test + rollback) |

`examples/` shows the caller workflows for each repo type.
Pin callers to a tag (`@v1`) so template changes roll out deliberately.

Service accounts expected (create in stage 3 or project factory):
`ci-build@<artifacts project>` (artifactregistry.writer), `deployer@<gke project>` (container.developer, from project factory).

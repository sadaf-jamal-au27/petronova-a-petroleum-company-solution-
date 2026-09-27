# petronova-deployments
`dev/`, `prod/` (primary cluster, asia-south1) and `prod-dr/` (warm standby, asia-south2, replicas 0).
A merged PR is a deployment; `scripts/deploy.sh <env> <service>` runs `helm upgrade --install --atomic` then `helm test`.
Promotion copies the same chart and image versions from dev to prod and prod-dr (never rebuilt).

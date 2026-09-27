# Policy guardrails

Enable **Policy Controller** (managed Gatekeeper) from Fleet and apply the bundled
`pss-restricted-v2022` and `cis-gke-v1.5.0` policy bundles in dryrun first:

```bash
gcloud container fleet policycontroller enable --memberships=petronova-dev \
  --referential-rules --template-library-installation-mode=ALL
```

PetroNova-specific constraints are in `constraints/`:

- `require-team-label.yaml` - every Deployment/CronJob must carry `petronova.io/team`
- `allowed-repos.yaml` - images only from the PetroNova Artifact Registry

# PetroNova: Implementation Guide

Lab mode = dev only + POC site simulator over HA VPN (no carrier circuits needed). Production adds Interconnect and the DR region.
Tools: gcloud, terraform >= 1.12 (or OpenTofu >= 1.11), helm >= 3.15, kubectl, yq v4, docker, Python 3.12.

## Phase 0: Local logic check (1 hour, no cloud)
`cd 05-services && pip install -r mqtt-bridge/requirements.txt pytest && pytest tests`
`cd 06-data-pipelines/dataflow && pytest test_transforms.py`

## Phase 1: Landing zone with FAST v58 (weeks 1-2)
1. Cloud Identity org + groups: gcp-organization-admins, gcp-network-admins, gcp-security-admins, gcp-platform-team,
   pn-ot-engineering, pn-data-team, pn-app-squads, pn-soc-analysts, pn-auditors.
2. Replace placeholders (`pnlab01`, `petronova-lab.in`, site public IPs, Interconnect URLs, VPN secrets).
3. `01-landing-zone`: `scripts/prereqs.sh`, then `scripts/fast.sh <stage> link|init|apply` for
   0-org-setup -> 2-security -> 2-networking -> 2-project-factory (same flow as the README in that folder).
4. **Lab tip:** before 2-networking, move `vpcs/hub/vlan-attachments/*.yaml` and `vpcs/hub/vpns/*.yaml` out of the dataset
   (no real circuits or peers yet). The POC site in stage 3 provides the hybrid link.
- **Done:** NCC hub shows hub, prod and dev spokes; `gcloud compute routers list` shows ic-as1, ic-as2, pic-as1, vpn-as1.

## Phase 2: Stage 3 + POC hybrid site (week 3)
1. Create project `pnlab01-dev-sitesim-0` (or add it to the project factory under Networking).
2. `02-platform-infra`: fill `dev.tfvars` (set `poc_site.enabled=true`, `edge_image` empty for now), `terraform apply`.
3. Verify BGP: `gcloud compute routers get-status hub-poc-site-router --region asia-south1 --project pnlab01-prod-net-core-0`
   learned routes must contain **only 172.21.0.0/24**.
- **Done:** 2 tunnels ESTABLISHED, BGP up, site learns only dev spoke + PGA ranges.

## Phase 3: Platform on GKE (week 4)
1. Issue certs: CAS pool (or `openssl` for lab) -> secrets `mosquitto-server-tls` (ot-ingest), `mqtt-bridge-client-tls`.
2. Package `03-platform-charts/energy-common` and push to Artifact Registry (OCI); run `helm lint --strict` on every chart.
3. `07-deployments/scripts/bootstrap-platform.sh` (tenants, ESO, gateway, mosquitto on internal LB 10.130.4.10).

## Phase 4: Services + pipeline (weeks 5-6)
1. Build/push images for all `05-services/*` and `06-data-pipelines/dataflow`.
2. `07-deployments/scripts/deploy.sh dev <service>` for mqtt-bridge, alarm-service, timeseries-api, asset-registry, workorder-service, operator-portal.
3. `06-data-pipelines/dataflow/deploy.sh dev asia-south1`.
4. Set `edge_image` in dev.tfvars, re-apply: the edge VM in the simulated DMZ starts publishing.
- **Done:** POC criteria 9.1 in the solution design (alarm < 10 s, BigQuery < 60 s).

## Phase 5: Security, audit, DR (weeks 7-8)
- `10-security`: VPC-SC dry-run, SecOps rules, `evidence/evidence.sh` monthly.
- `09-observability`: `terraform apply` (BGP, VPN, Interconnect, backlog, lag, site-silent alerts).
- Link-loss drill: disable the site router peers for 15 min; check edge buffer replay, no duplicates in BigQuery.
- Prod: `prod.tfvars` with `dr_enabled=true`; deploy `prod/` and `prod-dr/`; run `11-dr/failover.sh` (dry run, then game day).

## Cost control (lab)
`terraform destroy` stage 3 after demos; HA VPN costs per tunnel-hour; Bigtable is the largest POC line item (1 node).

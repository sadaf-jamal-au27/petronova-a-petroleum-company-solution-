# PetroNova: Hybrid OT/IT Energy Platform on GCP (implementation kit)

Oil and gas reference implementation: FAST landing zone with NCC hub-and-spoke and hybrid connectivity
(Dedicated/Partner Interconnect + HA VPN), Purdue/IEC 62443-aligned OT isolation, telemetry platform on GKE + Helm,
Dataflow/Bigtable/BigQuery/Vertex AI, security operations, audit evidence and DR.

```
01-landing-zone      FAST v58.0.0 datasets: org policies, CMEK (2 regions), NCC hub, Interconnect VLANs, HA VPN, spokes, DNS
02-platform-infra    Stage 3: regional GKE (+DR), Pub/Sub, Bigtable multi-cluster, BigQuery, dual-region GCS, Cloud SQL + DR replica,
                     POC plant-DMZ simulator with GCP-to-GCP HA VPN + edge VM
03-platform-charts   energy-common library chart, tenant chart, platform add-ons (ESO, internal gateway, Gatekeeper)
04-contracts         Telemetry batch JSON schema, alarm Avro, BigQuery table schemas
05-services          edge-simulator (store-and-forward), mosquitto (mTLS), mqtt-bridge, alarm, workorder, asset, timeseries, portal
06-data-pipelines    Dataflow streaming pipeline, BigQuery SQL features, Vertex AI (BQML) training pipeline
07-deployments       dev / prod / prod-dr release files, deploy + bootstrap scripts
08-ci-templates      Reusable GitHub Actions (keyless WIF)
09-observability     Hybrid + ingest alerting (BGP, VPN, Interconnect, backlog, lag, site silent)
10-security          VPC-SC perimeter, SecOps YARA-L rules, IEC 62443 control matrix, evidence pack script
11-dr                Failover script (dry-run default), DR test report template
docs/                Implementation guide, POC demo runbook, operational runbooks
```

## Verified before packaging
| Item | Check | Result |
|---|---|---|
| FAST datasets (71 files incl. VLAN attachments, VPNs, NCC, NGFW policy, org policies) | JSON schema vs Fabric v58.0.0 | pass |
| Stage 3 + observability Terraform | `tofu validate` (OpenTofu 1.11, google 7.45) + fmt | pass |
| Services logic (edge buffer/replay, contract validation, alarm to work order, Bigtable keys) | pytest | 4 passed |
| Dataflow transforms (parse, replay dedupe, anomaly, keys) | pytest | 3 passed |
| All YAML | parse + duplicate keys | pass |
| Helm charts, YARA-L rules, VPC-SC YAML | **not executed here** (no helm/SecOps in sandbox) | run `helm lint --strict`; validate rules in SecOps editor |

Placeholders: `pnlab01`, `petronova-lab.in`, `petronova-org`, 203.0.113.x site IPs, Interconnect URLs, VPN shared secrets,
`NETWORKING_FOLDER_ID`. Find them: `grep -rn "pnlab01\|petronova-lab\|203.0.113\|REPLACE" .`
# petronova-a-petroleum-company-solution-

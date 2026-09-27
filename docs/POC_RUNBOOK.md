# POC runbook (client demo, ~30 minutes)

| # | Show | Command / screen | What the client sees |
|---|---|---|---|
| 1 | Landing zone | Console: Resource Manager + Org Policies | Folders per zone, no SA keys, residency policy |
| 2 | Hybrid link | `gcloud compute routers get-status hub-poc-site-router ...` | BGP up; cloud learns only the DMZ prefix |
| 3 | OT isolation | From a GKE pod: `nc -zv 172.21.0.10 22` | Timeout; deny logged in site firewall logs |
| 4 | Live telemetry | Operator portal + `timeseries-api /series` | Compressor K-101 trends in seconds |
| 5 | Anomaly | Edge injects bearing defect after 120 s | CRITICAL alarm, then DRAFT work order awaiting approval |
| 6 | Link loss | Disable router peers 5 min, then re-enable | Edge buffers, replays; BigQuery shows no gap, no duplicates |
| 7 | Security ops | SCC findings, SecOps rule on new BGP prefix | Detection + response playbook |
| 8 | Audit | `10-security/evidence/evidence.sh` | Evidence pack with SHA-256 manifest |
| 9 | DR | `11-dr/failover.sh` (dry run) | Scripted, timed failover plan |

Talking points: no inbound path to OT, private-only connectivity, 72-hour buffering, audit evidence generated not collected.

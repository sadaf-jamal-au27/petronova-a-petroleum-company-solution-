# Security and audit kit

| Path | Purpose |
|---|---|
| `vpc-sc/perimeters.yaml` | `ot-data` perimeter with ingress rules for mqtt-bridge and timeseries-api; dry-run first |
| `secops-rules/*.yaral` | Google SecOps (YARA-L 2.0) detections: unexpected BGP prefix, VPN to unknown peer, bulk BigQuery export |
| `iec62443-control-matrix.csv` | Control mapping IEC 62443 / NIST CSF 2.0 / ISO 27001 with automated check and evidence artefact |
| `evidence/evidence.sh` | Monthly read-only evidence pack with SHA-256 manifest, stored in a locked bucket |

Validate YARA-L rules in the SecOps rules editor before enabling; field names depend on your log parsers.

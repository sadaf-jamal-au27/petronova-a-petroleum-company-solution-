# Runbooks

## Hybrid: BGP session down
1. `gcloud compute routers get-status <router> --region <r> --project pnlab01-prod-net-core-0` - which peer?
2. Interconnect: check attachment state and circuit (`gcloud compute interconnects describe`); VPN: tunnel status and IKE logs.
3. Traffic should already be on the backup path (HA VPN or other EAD). Open a carrier ticket; no OT action needed.

## Ingest: site silent
1. Is BGP up for that site? If not, see above; edges are buffering (72 h capacity).
2. If BGP is up: mosquitto logs (TLS/cert errors), mqtt-bridge rejects metric, edge certificate expiry.

## Ingest backlog / Dataflow lag
Check Dataflow autoscaling and Bigtable CPU (> 70% add nodes). Replays after long outages raise backlog temporarily; expected.

## Suspected OT exposure (unexpected BGP prefix)
SOC playbook: withdraw the site's advertisements on the cloud router (set peer `--advertisement-mode CUSTOM` with no ranges or disable peer),
notify site OT lead, preserve logs, CERT-In notification within 6 hours if confirmed.

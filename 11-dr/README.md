# Disaster recovery kit

- `failover.sh` - scripted Tier-1/2 regional failover (dry run by default, `--execute` to act).
- `dr-test-report-template.md` - evidence template for game days (quarterly link tests, half-yearly regional).
- Link failure drill: `gcloud compute interconnects attachments update hq-as1-ead1 --region asia-south1 --no-admin-enabled`
  (POC: `gcloud compute vpn-tunnels delete hub-to-site-t0 ...` via `terraform apply -var poc_site...` or disable the site router peer).

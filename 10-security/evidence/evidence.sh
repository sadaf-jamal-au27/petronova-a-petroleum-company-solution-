#!/usr/bin/env bash
# Monthly audit evidence pack (read-only). Run as evidence-exporter SA (roles: viewer, securityReviewer, cloudasset.viewer).
# Output: evidence-YYYY-MM/ + tarball + SHA-256 manifest, uploaded to the locked audit bucket.
set -euo pipefail
ORG=${ORG_ID:?}; PREFIX=${PREFIX:-pnlab01}; OUT=evidence-$(date +%Y-%m); mkdir -p "$OUT"
HUB=$PREFIX-prod-net-core-0
gcloud org-policies list --organization "$ORG" --format=json > "$OUT/org-policies.json"
gcloud asset search-all-iam-policies --scope "organizations/$ORG" --format=json > "$OUT/iam-bindings.json"
gcloud asset search-all-resources --scope "organizations/$ORG" --asset-types=iam.googleapis.com/ServiceAccountKey \
  --query="keyType=USER_MANAGED" --format=json > "$OUT/sa-keys.json"
gcloud asset search-all-resources --scope "organizations/$ORG" --asset-types=cloudkms.googleapis.com/CryptoKey --format=json > "$OUT/kms-keys.json"
gcloud logging sinks list --organization "$ORG" --format=json > "$OUT/log-sinks.json"
gcloud compute firewall-rules list --project "$HUB" --format=json > "$OUT/firewall-rules.json"
gcloud compute interconnects attachments list --project "$HUB" --format=json > "$OUT/interconnect-attachments.json"
gcloud compute vpn-tunnels list --project "$HUB" --format=json > "$OUT/vpn-tunnels.json"
for r in $(gcloud compute routers list --project "$HUB" --format="value(name,region)" | tr '\t' ','); do
  n=${r%,*}; reg=${r#*,}
  gcloud compute routers get-status "$n" --region "${reg##*/}" --project "$HUB" --format=json > "$OUT/bgp-$n.json"
done
gcloud scc findings list "organizations/$ORG" --filter='state="ACTIVE" AND severity=("HIGH" OR "CRITICAL")' --format=json > "$OUT/scc-findings.json" || true
( cd "$OUT" && sha256sum * > MANIFEST.sha256 )
tar czf "$OUT.tgz" "$OUT"
gcloud storage cp "$OUT.tgz" "gs://$PREFIX-prod-secops-0-audit-evidence/"
echo "evidence pack: $OUT.tgz"

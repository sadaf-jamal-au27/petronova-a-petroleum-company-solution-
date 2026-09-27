#!/usr/bin/env bash
# Tier-1/2 regional failover asia-south1 -> asia-south2 (see solution design section 7.3).
# Dry run by default; pass --execute to act. Each step prints what it changes.
set -euo pipefail
EXEC=${1:-}; P=pnlab01; APPS=$P-prod-apps-0
run(){ echo "+ $*"; [ "$EXEC" = "--execute" ] && eval "$@" || true; }
echo "== 1. Promote Cloud SQL cross-region replica"
run gcloud sql instances promote-replica pn-apps-prod-dr --project $APPS --quiet
echo "== 2. Point DR releases at the promoted DB and scale up"
run gcloud container clusters get-credentials petronova-prod-dr --region asia-south2 --project $APPS
for s in mqtt-bridge alarm-service timeseries-api asset-registry workorder-service operator-portal; do
  ns=$([ $s = mqtt-bridge ] && echo ot-ingest || echo operations)
  run helm upgrade $s oci://asia-south1-docker.pkg.dev/$P-prod-artifacts-0/helm-charts/$s --reuse-values -n $ns \
      --set replicaCount=3 --set autoscaling.enabled=true --set autoscaling.minReplicas=3 --atomic --wait
done
run helm upgrade mosquitto ../05-services/mosquitto/chart -n ot-ingest --reuse-values --set replicas=1 --set loadBalancerIP=10.120.4.10
echo "== 3. Launch Dataflow in asia-south2"
run ../06-data-pipelines/dataflow/deploy.sh prod asia-south2
echo "== 4. Repoint DNS for edges and operators"
run gcloud dns record-sets update mqtt-prod.gcp.petronova.internal. --type A --ttl 60 --rrdatas 10.120.4.10 \
    --zone gcp-petronova-internal --project $P-prod-net-core-0
echo "== 5. Verify: edges reconnect and replay; check freshness"
run bq query --use_legacy_sql=false "'SELECT site, MAX(ts) AS last_point FROM \`$P-prod-data-0.curated.telemetry\` GROUP BY site'"
echo "Done. Record timings in dr-test-report template."

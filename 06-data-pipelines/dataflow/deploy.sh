#!/usr/bin/env bash
# Build the Flex Template and launch the streaming job (private IPs, CMEK, spoke subnet).
# Usage: ./deploy.sh dev asia-south1   (DR: ./deploy.sh prod asia-south2)
set -euo pipefail
ENV=${1:?env}; REGION=${2:-asia-south1}
P=pnlab01; DATA=$P-$ENV-data-0; INGEST=$P-$ENV-ingest-0
IMG=asia-south1-docker.pkg.dev/$P-prod-artifacts-0/docker-images/telemetry-pipeline:1.0.0
SUBNET=$([ "$REGION" = asia-south1 ] && echo data-$ENV-as1 || echo data-$ENV-as2)
KEY=projects/$P-$ENV-sec-core-0/locations/$REGION/keyRings/$ENV$([ "$REGION" = asia-south2 ] && echo -dr)-petronova/cryptoKeys/compute
gcloud builds submit --tag "$IMG" .   # or docker build/push from CI
gcloud dataflow flex-template build gs://$DATA-dataflow/templates/telemetry.json --image "$IMG" --sdk-language PYTHON
gcloud dataflow flex-template run "telemetry-$ENV-$(date +%Y%m%d%H%M)" --project $DATA --region $REGION \
  --template-file-gcs-location gs://$DATA-dataflow/templates/telemetry.json \
  --service-account-email dataflow-worker@$DATA.iam.gserviceaccount.com \
  --subnetwork "https://www.googleapis.com/compute/v1/projects/$P-$ENV-net-spoke-0/regions/$REGION/subnetworks/$SUBNET" \
  --disable-public-ips --dataflow-kms-key "$KEY" --enable-streaming-engine \
  --parameters input_subscription=projects/$INGEST/subscriptions/telemetry-raw-dataflow,anomaly_topic=projects/$INGEST/topics/telemetry-anomaly,bq_table=$DATA:curated.telemetry,bigtable_project=$DATA,bigtable_instance=pn-telemetry-$ENV

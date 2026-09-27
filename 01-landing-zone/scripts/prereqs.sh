#!/usr/bin/env bash
# Phase 1a: one-time prerequisites for FAST 0-org-setup.
# Run as the initial Organization Admin (a member of gcp-organization-admins).
set -euo pipefail
: "${FAST_ORG_ID:?export FAST_ORG_ID (gcloud organizations list)}"
: "${FAST_DOMAIN:?export FAST_DOMAIN (e.g. petronova-lab.in)}"
: "${BOOTSTRAP_PROJECT:?export BOOTSTRAP_PROJECT (temporary project linked to billing)}"
FAST_PRINCIPAL="group:gcp-organization-admins@${FAST_DOMAIN}"

echo ">> Granting bootstrap roles to ${FAST_PRINCIPAL}"
for role in roles/billing.admin roles/logging.admin roles/iam.organizationRoleAdmin \
  roles/orgpolicy.policyAdmin roles/resourcemanager.folderAdmin \
  roles/resourcemanager.organizationAdmin roles/resourcemanager.projectCreator \
  roles/resourcemanager.tagAdmin roles/owner; do
  gcloud organizations add-iam-policy-binding "$FAST_ORG_ID" \
    --member "$FAST_PRINCIPAL" --role "$role" --condition None --quiet >/dev/null
done

echo ">> Preparing temporary bootstrap project ${BOOTSTRAP_PROJECT}"
gcloud config set project "$BOOTSTRAP_PROJECT"
gcloud services enable bigquery.googleapis.com cloudbilling.googleapis.com \
  cloudresourcemanager.googleapis.com essentialcontacts.googleapis.com iam.googleapis.com \
  logging.googleapis.com orgpolicy.googleapis.com serviceusage.googleapis.com

echo ">> Org policies already set (add these to org_policies_imports):"
gcloud org-policies list --organization "$FAST_ORG_ID" --format="value(constraint)" \
  | sed 's#constraints/##' | awk '{printf "  \"%s\",\n", $1}'
echo ">> Done. Next: scripts/fast.sh 0-org-setup apply"

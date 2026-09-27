#!/usr/bin/env bash
# Run a FAST stage against the PetroNova datasets in this repo.
# Usage: scripts/fast.sh <0-org-setup|2-security|2-networking|2-project-factory> <init|plan|apply|link>
set -euo pipefail
STAGE=${1:?stage}; ACTION=${2:?action}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(cat "$ROOT/FAST_VERSION")
OUT=${FAST_OUTPUTS:-$HOME/fast-config/petronova}
FABRIC="$ROOT/.fabric"

if [ ! -d "$FABRIC" ]; then
  git clone --depth 1 --branch "$VERSION" https://github.com/GoogleCloudPlatform/cloud-foundation-fabric.git "$FABRIC"
fi
cd "$FABRIC/fast/stages/$STAGE"

# Point the stage at our dataset (kept in Git, outside the vendored Fabric copy)
cat > petronova.auto.tfvars <<TFV
factories_config = {
  dataset = "$ROOT/${STAGE}-dataset"
}
TFV
if [ "$STAGE" = "0-org-setup" ] && [ -f "$ROOT/0-org-setup.imports.auto.tfvars" ]; then
  cp "$ROOT/0-org-setup.imports.auto.tfvars" ./
fi

case "$ACTION" in
  link)  # link provider + tfvars files produced by earlier stages
         ../fast-links.sh "$OUT" | bash ;;
  init)  terraform init ;;
  migrate) terraform init -migrate-state ;;
  plan)  terraform plan -out tfplan ;;
  apply) terraform apply ;;
  *) echo "unknown action $ACTION"; exit 1 ;;
esac

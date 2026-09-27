#!/usr/bin/env bash
# Deploy one service to an environment from its deployment file.
# Usage: scripts/deploy.sh <dev|prod> <service>
set -euo pipefail
ENV=${1:?env}; SVC=${2:?service}
cd "$(dirname "$0")/.."
F="$ENV/$SVC.yaml"
release=$(yq '.release' "$F"); ns=$(yq '.namespace' "$F")
chart=$(yq '.chart' "$F"); ver=$(yq '.chartVersion' "$F"); tag=$(yq '.imageTag' "$F")

TMP=$(mktemp -d); trap 'rm -rf $TMP' EXIT
yq '.overrides' "$F" > "$TMP/overrides.yaml"
ARGS=()
if [ "$(yq '.valuesFiles | length' "$F")" != "0" ]; then
  helm pull "$chart" --version "$ver" --untar -d "$TMP"
  for vf in $(yq '.valuesFiles[]' "$F"); do ARGS+=(-f "$TMP/$(basename "$chart")/$vf"); done
fi

echo ">> $release $ver (image $tag) -> $ns [$ENV]"
helm upgrade --install "$release" "$chart" --version "$ver" -n "$ns" \
  "${ARGS[@]}" -f "$TMP/overrides.yaml" --set image.tag="$tag" \
  --atomic --wait --timeout 10m --history-max 10
helm test "$release" -n "$ns" --logs || { echo "helm test failed, rolling back"; helm rollback "$release" 0 -n "$ns" --wait; exit 1; }

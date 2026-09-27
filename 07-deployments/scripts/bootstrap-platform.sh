#!/usr/bin/env bash
# Install platform releases in order (Phase 2-4, 7). Requires: helm >= 3.15, yq v4, kubectl context set.
set -euo pipefail
cd "$(dirname "$0")/.."
FILE=platform/releases.yaml
N=$(yq 'length' $FILE)
for i in $(seq 0 $((N-1))); do
  name=$(yq ".[$i].name" $FILE); chart=$(yq ".[$i].chart" $FILE); ns=$(yq ".[$i].namespace" $FILE)
  repo=$(yq ".[$i].repo // \"\"" $FILE); ver=$(yq ".[$i].version // \"\"" $FILE)
  vals=$(yq ".[$i].values[]" $FILE | sed 's/^/-f /' | tr '\n' ' ')
  if [ -n "$repo" ]; then helm repo add "${chart%%/*}" "$repo" >/dev/null 2>&1 || true; helm repo update >/dev/null; fi
    echo ">> $name ($chart) -> $ns"
  helm upgrade --install "$name" "$chart" -n "$ns" --create-namespace \
    ${ver:+--version $ver} $vals --atomic --wait --timeout 15m
done

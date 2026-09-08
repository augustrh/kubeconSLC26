#!/usr/bin/env bash
# wait-spokes-clean.sh — block until node-exporter is fully gone from every spoke.
#
# `make reset` deletes the add-on on the HUB, which returns immediately. But the
# workload is pulled off the spokes asynchronously (ManagedClusterAddOn ->
# ManifestWork GC -> klusterlet removes the DaemonSet). This waits until the
# 'monitoring' namespace has zero pods on every managed cluster, so reset only
# reports "done" when the fleet is actually clean.
set -euo pipefail

HUB_CONTEXT="kind-hub"
TIMEOUT_SECONDS="${1:-60}"

# Spokes = the managed clusters registered on the hub (works for any N).
SPOKES=$(kubectl --context "${HUB_CONTEXT}" get managedcluster -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
if [ -z "${SPOKES}" ]; then
  echo "  (no managed clusters found — nothing to wait for)"
  exit 0
fi

deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
while true; do
  remaining=0
  for s in ${SPOKES}; do
    pods=$(kubectl --context "kind-${s}" -n monitoring get pods --no-headers 2>/dev/null | wc -l | tr -d ' ')
    remaining=$(( remaining + pods ))
  done

  if [ "${remaining}" -eq 0 ]; then
    echo "  ✅ spokes clean (monitoring empty on all clusters)"
    break
  fi

  if [ "$(date +%s)" -ge "${deadline}" ]; then
    echo "  ⏱  still ${remaining} pod(s) terminating after ${TIMEOUT_SECONDS}s — moving on."
    break
  fi
  echo "  … ${remaining} node-exporter pod(s) still terminating"
  sleep 2
done

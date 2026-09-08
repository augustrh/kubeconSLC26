#!/usr/bin/env bash
# showtime.sh — the live-demo deploy button.
#
# Runs the three "payoff" steps as one calm, self-terminating flow:
#   1. apply the add-on bundle to the hub
#   2. watch the rollout until every add-on is Available (then STOP — no hanging -w)
#   3. show node-exporter pods on each spoke, one block per cluster
#
# Usage:
#   ./hack/showtime.sh                 # applies ./ocm-addon-output (your live skill run)
#   ./hack/showtime.sh ./break-glass   # applies the known-good fallback instead
set -euo pipefail

BUNDLE="${1:-./ocm-addon-output}"
HUB_CONTEXT="kind-hub"
TIMEOUT_SECONDS=180

if [ ! -d "${BUNDLE}" ]; then
  echo "Bundle directory '${BUNDLE}' not found." >&2
  exit 1
fi

echo "▶ Applying add-on bundle from ${BUNDLE} (on the hub) ..."
kubectl --context "${HUB_CONTEXT}" apply -f "${BUNDLE}"
echo

# Spokes = the managed clusters registered on the hub (works for any N).
SPOKES=$(kubectl --context "${HUB_CONTEXT}" get managedcluster -o jsonpath='{.items[*].metadata.name}')
EXPECTED=$(echo "${SPOKES}" | wc -w | tr -d ' ')

deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
while true; do
  clear
  echo "=== node-exporter rollout — waiting for pods Ready on ${EXPECTED} cluster(s) ==="
  echo
  echo "Add-on status (hub view):"
  kubectl --context "${HUB_CONTEXT}" get managedclusteraddon -A || true

  # Hub-side: add-on installed/Available on every cluster.
  avail=$(kubectl --context "${HUB_CONTEXT}" get managedclusteraddon -A \
            -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Available")].status}{"\n"}{end}' 2>/dev/null \
            | grep -c '^True$' || true)

  # Spoke-side: the REAL signal — node-exporter pods actually Running/Ready.
  # The add-on can report Available before the DaemonSet pods finish starting,
  # so we gate on the workload itself, per spoke.
  echo
  echo "Workload (node-exporter pods in 'monitoring', spoke view):"
  ready_spokes=0
  for s in ${SPOKES}; do
    total_pods=$(kubectl --context "kind-${s}" -n monitoring get pods --no-headers 2>/dev/null | wc -l | tr -d ' ')
    ready_pods=$(kubectl --context "kind-${s}" -n monitoring get pods \
                   -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null \
                   | grep -c '^True$' || true)
    if [ "${total_pods}" -gt 0 ] && [ "${ready_pods}" = "${total_pods}" ]; then
      echo "  ${s}: ${ready_pods}/${total_pods} Ready ✅"
      ready_spokes=$(( ready_spokes + 1 ))
    else
      echo "  ${s}: ${ready_pods}/${total_pods} Ready …"
    fi
  done

  if [ "${avail}" = "${EXPECTED}" ] && [ "${ready_spokes}" = "${EXPECTED}" ]; then
    echo
    echo "✅ node-exporter is Available and Ready on all ${EXPECTED} cluster(s)."
    break
  fi

  if [ "$(date +%s)" -ge "${deadline}" ]; then
    echo
    echo "⏱  Timed out after ${TIMEOUT_SECONDS}s. Showing current state anyway."
    break
  fi
  sleep 3
done

echo
echo "▶ node-exporter on each spoke (one pod per node):"
for s in ${SPOKES}; do
  echo
  echo "--- ${s} ---"
  kubectl --context "kind-${s}" get pods -n monitoring -o wide || true
done
echo
echo "Three objects, one placement, and the hub did the rest."

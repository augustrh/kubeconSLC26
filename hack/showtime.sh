#!/usr/bin/env bash
# showtime.sh — the live-demo deploy button.
#
# Runs the "payoff" steps as one calm flow:
#   1. apply the add-on bundle to the hub
#   2. live-refresh the rollout (status + "meanwhile" diagram) until every add-on
#      is Available AND its pods are Ready per spoke
#   3. once done, show node-exporter pods per spoke and HOLD on the finished screen,
#      refreshing in place, until you press Ctrl-C. (No hanging -w; nothing scrolls
#      away on stage.)
#
# Usage:
#   ./hack/showtime.sh                 # applies ./ocm-addon-output (your live skill run)
#   ./hack/showtime.sh ./break-glass   # applies the known-good fallback instead
set -euo pipefail

BUNDLE="${1:-./ocm-addon-output}"
HUB_CONTEXT="kind-hub"

if [ ! -d "${BUNDLE}" ]; then
  echo "Bundle directory '${BUNDLE}' not found." >&2
  exit 1
fi

echo "▶ Applying add-on bundle from ${BUNDLE} (on the hub) ..."
echo "  \$ kubectl --context ${HUB_CONTEXT} apply -f ${BUNDLE}"
kubectl --context "${HUB_CONTEXT}" apply -f "${BUNDLE}"
echo

# Spokes = the managed clusters registered on the hub (works for any N).
SPOKES=$(kubectl --context "${HUB_CONTEXT}" get managedcluster -o jsonpath='{.items[*].metadata.name}')
EXPECTED=$(echo "${SPOKES}" | wc -w | tr -d ' ')

# "Meanwhile, the hub is doing the work" diagram — shown under the live status on
# every refresh so the audience sees what's happening during the rollout gap.
# Mirrors docs/rollout-stage-notes.md; keep the two in sync if you edit either.
read -r -d '' ROLLOUT_DIAGRAM <<'ART' || true
─────────────────────────  meanwhile, the hub is doing the work  ─────────────────────────


     YOU  ──▶  kubectl apply     (4 objects, once, on the HUB)
      │
      ▼   HUB
     ClusterManagementAddOn  ──(installStrategy)──▶  Placement  ──▶  PlacementDecision
          │  addon-manager owns it                                     [ the fleet ]
          │
          ▼   for EACH selected cluster:
     ManagedClusterAddOn  ──renders AddOnTemplate + vars  ({{IMAGE_TAG}}, {{LOG_LEVEL}})
          │
          ▼   ships a ManifestWork down to each spoke
     ┌──── spoke ────┐    klusterlet applies Namespace + DaemonSet,
     │  node-exporter │    node-exporter pods start, report healthy  ──▶  back to hub
     └───────────────┘
          │
          ▼
     AVAILABLE = True     (per cluster)


──────────────────────────────────────────────────────────────────────────────────────
ART

# Clean exit on Ctrl-C — the loop never self-terminates, so this is how you leave.
trap 'printf "\n\n👋 done — exiting showtime.\n"; exit 0' INT

start=$(date +%s)
while true; do
  elapsed=$(( $(date +%s) - start ))

  # Hub-side: add-on installed/Available on every cluster.
  avail=$(kubectl --context "${HUB_CONTEXT}" get managedclusteraddon -A \
            -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Available")].status}{"\n"}{end}' 2>/dev/null \
            | grep -c '^True$' || true)

  # Spoke-side: the REAL signal — node-exporter pods actually Running/Ready. The
  # add-on can report Available before the DaemonSet pods finish starting, so we
  # gate on the workload itself, per spoke. Build the display lines up front so we
  # know whether we're "done" before we paint the screen.
  ready_spokes=0
  spoke_lines=""
  for s in ${SPOKES}; do
    total_pods=$(kubectl --context "kind-${s}" -n monitoring get pods --no-headers 2>/dev/null | wc -l | tr -d ' ')
    ready_pods=$(kubectl --context "kind-${s}" -n monitoring get pods \
                   -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null \
                   | grep -c '^True$' || true)
    if [ "${total_pods}" -gt 0 ] && [ "${ready_pods}" = "${total_pods}" ]; then
      spoke_lines+="  ${s}: ${ready_pods}/${total_pods} Ready ✅"$'\n'
      ready_spokes=$(( ready_spokes + 1 ))
    else
      spoke_lines+="  ${s}: ${ready_pods}/${total_pods} Ready …"$'\n'
    fi
  done

  done_now=0
  if [ "${avail}" = "${EXPECTED}" ] && [ "${ready_spokes}" = "${EXPECTED}" ]; then
    done_now=1
  fi

  # ---- paint the screen ----
  clear
  if [ "${done_now}" = "1" ]; then
    echo "=== node-exporter rollout — ✅ DONE on ${EXPECTED} cluster(s)  (holding — press Ctrl-C to exit) ==="
  else
    echo "=== node-exporter rollout — waiting for pods Ready on ${EXPECTED} cluster(s)  (${elapsed}s elapsed) ==="
  fi
  echo
  echo "Add-on status (hub view):"
  echo "  \$ kubectl --context ${HUB_CONTEXT} get managedclusteraddon -A"
  kubectl --context "${HUB_CONTEXT}" get managedclusteraddon -A || true
  echo
  echo "Workload (node-exporter pods in 'monitoring', spoke view):"
  echo "  \$ kubectl --context kind-<spoke> -n monitoring get pods"
  printf '%s' "${spoke_lines}"
  echo
  echo "${ROLLOUT_DIAGRAM}"

  if [ "${done_now}" = "1" ]; then
    echo
    echo "node-exporter pods — one per node, across the fleet:"
    printf "   %-10s %-22s %-9s %s\n" "CLUSTER" "POD" "STATUS" "NODE"
    for s in ${SPOKES}; do
      while read -r pod status node; do
        [ -z "${pod}" ] && continue
        printf "   %-10s %-22s %-9s %s\n" "${s}" "${pod}" "${status}" "${node}"
      done < <(kubectl --context "kind-${s}" get pods -n monitoring \
                 -o custom-columns="POD:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName" \
                 --no-headers 2>/dev/null)
    done
    echo
    echo "   Three objects, one placement, and the hub did the rest."
    echo
    echo "(holding on the finished rollout — press Ctrl-C when you're ready to move on)"
  fi

  sleep 3
done

#!/usr/bin/env bash
set -e

NUM_CLUSTERS=${1:-2}
HUB_NAME="hub"

echo "=== Creating OCM Hub Cluster: ${HUB_NAME} ==="
if kind get clusters 2>/dev/null | grep -qx "${HUB_NAME}"; then
  echo "  [skip] kind cluster '${HUB_NAME}' already exists"
else
  kind create cluster --name "${HUB_NAME}" --config - <<EOF
apiVersion: kind.x-k8s.io/v1alpha4
kind: Cluster
nodes:
- role: control-plane
EOF
fi

# Install clusteradm CLI if missing
if ! command -v clusteradm &> /dev/null; then
    echo "=== Installing clusteradm CLI ==="
    curl -L https://raw.githubusercontent.com/open-cluster-management-io/clusteradm/main/install.sh | bash
fi

echo "=== Initializing OCM Hub ==="
kubectl config use-context "kind-${HUB_NAME}"
clusteradm init --wait

# Extract join command. `clusteradm get token` prints it with a literal
# placeholder `--cluster-name <cluster_name>`; the angle brackets would be read
# by the shell as a redirect, so strip that arg and add the real one below.
JOIN_CMD=$(clusteradm get token | grep "clusteradm join" | sed 's/[[:space:]]*--cluster-name[[:space:]]*<cluster_name>//')

for i in $(seq 1 "${NUM_CLUSTERS}"); do
  SPOKE_NAME="cluster-${i}"

  # If the spoke is already a registered, accepted ManagedCluster on the hub, skip
  # it entirely. Re-running join mints a NEW bootstrap CSR each time, and multiple
  # pending CSRs from different requesters block `clusteradm accept`.
  if kubectl --context "kind-${HUB_NAME}" get managedcluster "${SPOKE_NAME}" \
       -o jsonpath='{.spec.hubAcceptsClient}' 2>/dev/null | grep -qx true; then
    echo "=== ${SPOKE_NAME} already joined and accepted, skipping ==="
    continue
  fi

  echo "=== Creating Spoke Cluster: ${SPOKE_NAME} ==="
  if kind get clusters 2>/dev/null | grep -qx "${SPOKE_NAME}"; then
    echo "  [skip] kind cluster '${SPOKE_NAME}' already exists"
  else
    kind create cluster --name "${SPOKE_NAME}"
  fi

  echo "=== Joining ${SPOKE_NAME} to Hub ==="
  kubectl config use-context "kind-${SPOKE_NAME}"
  eval "${JOIN_CMD} --cluster-name ${SPOKE_NAME} --force-internal-endpoint-lookup"

  echo "=== Accepting ${SPOKE_NAME} on Hub ==="
  kubectl config use-context "kind-${HUB_NAME}"
  # The spoke's registration agent needs a few seconds after join to submit its
  # CSR on the hub. accept fails fast if the CSR isn't there yet, so retry.
  # --skip-approve-check approves all pending CSRs for the cluster (handles the
  # case where more than one CSR is present).
  accepted=false
  for attempt in $(seq 1 30); do
    if clusteradm accept --clusters "${SPOKE_NAME}" --skip-approve-check; then
      accepted=true
      break
    fi
    echo "  CSR for ${SPOKE_NAME} not ready yet (attempt ${attempt}/30), waiting 5s..."
    sleep 5
  done
  if [ "${accepted}" != "true" ]; then
    echo "  [ERROR] ${SPOKE_NAME} never presented a CSR to accept. Check the klusterlet on the spoke:"
    echo "          kubectl --context kind-${SPOKE_NAME} -n open-cluster-management-agent get pods"
    exit 1
  fi
done

echo "=== Binding the 'global' ManagedClusterSet into the 'default' namespace ==="
# Upstream OCM auto-creates the 'global' clusterset (DefaultClusterSet feature gate)
# but does NOT pre-bind it to a namespace. Without this binding a Placement in
# 'default' selects ZERO clusters, and the add-on would silently roll out to nothing.
kubectl config use-context "kind-${HUB_NAME}"
kubectl apply -f - <<EOF
apiVersion: cluster.open-cluster-management.io/v1beta2
kind: ManagedClusterSetBinding
metadata:
  name: global
  namespace: default
spec:
  clusterSet: global
EOF

echo "=== Sanity checks ==="
# The 'global' clusterset must exist (DefaultClusterSet feature gate on).
kubectl get managedclusterset global >/dev/null 2>&1 \
  && echo "  [ok] 'global' ManagedClusterSet present" \
  || echo "  [WARN] 'global' ManagedClusterSet missing — re-run 'clusteradm init --feature-gates=DefaultClusterSet=true'"

echo "=== Environment Ready! ${NUM_CLUSTERS} Managed Clusters Joined. ==="
kubectl get managedclusters
kubectl get managedclusterset

#!/usr/bin/env bash
set -e

NUM_CLUSTERS=${1:-2}
HUB_NAME="hub"

echo "=== Creating OCM Hub Cluster: ${HUB_NAME} ==="
kind create cluster --name "${HUB_NAME}" --config - <<EOF
apiVersion: kind.x-k8s.io/v1alpha4
kind: Cluster
nodes:
- role: control-plane
EOF

# Install clusteradm CLI if missing
if ! command -v clusteradm &> /dev/null; then
    echo "=== Installing clusteradm CLI ==="
    curl -L https://raw.githubusercontent.com/open-cluster-management-io/clusteradm/main/install.sh | bash
fi

echo "=== Initializing OCM Hub ==="
kubectl config use-context "kind-${HUB_NAME}"
clusteradm init --wait

# Extract join command
JOIN_CMD=$(clusteradm get token | grep "clusteradm join")

for i in $(seq 1 "${NUM_CLUSTERS}"); do
  SPOKE_NAME="cluster-${i}"
  echo "=== Creating Spoke Cluster: ${SPOKE_NAME} ==="
  kind create cluster --name "${SPOKE_NAME}"
  
  echo "=== Joining ${SPOKE_NAME} to Hub ==="
  kubectl config use-context "kind-${SPOKE_NAME}"
  eval "${JOIN_CMD} --cluster-name ${SPOKE_NAME} --force-internal-endpoint-lookup"
  
  echo "=== Accepting ${SPOKE_NAME} on Hub ==="
  kubectl config use-context "kind-${HUB_NAME}"
  clusteradm accept --clusters "${SPOKE_NAME}"
done

echo "=== Binding the 'global' ManagedClusterSet into the 'default' namespace ==="
# Upstream OCM auto-creates the 'global' clusterset (DefaultClusterSet feature gate)
# but does NOT pre-bind it to a namespace. Without this binding a Placement in
# 'default' selects ZERO clusters, and the add-on would silently roll out to nothing.
kubectl config use-context "kind-${HUB_NAME}"
kubectl apply -f - <<EOF
apiVersion: cluster.open-cluster-management.io/v1beta1
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

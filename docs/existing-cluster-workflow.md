# Using the OCM Add-On Skill with Existing Clusters

## Overview

This guide explains how to use the Open Cluster Management (OCM) Add-On Skill with an existing Kubernetes environment.

The workflow is intended for users who already have an operational OCM hub and one or more registered managed clusters.

Unlike the repository's automated environment setup, this workflow does not require creating new Kind clusters or reinstalling OCM components.

The example uses Prometheus Node Exporter to demonstrate how a Kubernetes DaemonSet can be converted into an OCM add-on and distributed to managed clusters.

## Prerequisites

Before proceeding, ensure that the following requirements are satisfied:

- An operational OCM hub cluster
- At least one registered and available managed cluster
- OCM add-on management components installed and configured
- `kubectl` configured with access to the hub and managed cluster
- Claude Code installed and authenticated
- The `ocm-addon-skill` installed in Claude Code

## 1. Verify the Existing OCM Environment

Check the registered managed clusters:

```bash
kubectl --context kind-hub get managedclusters
```

The target managed cluster should report:

- JOINED: True
- AVAILABLE: True

Check the available ManagedClusterSets:

```bash
kubectl --context kind-hub get managedclustersets
```

Replace `kind-hub` with the appropriate Kubernetes context for your environment.

## 2. Verify the ManagedClusterSetBinding

The Node Exporter example uses a Placement that selects clusters from the `global` ManagedClusterSet.

Check whether the `global` ManagedClusterSet is bound to the `default` namespace:

```bash
kubectl --context kind-hub -n default get managedclustersetbinding global
```

If the binding does not exist, create a YAML file containing:

```yaml
apiVersion: cluster.open-cluster-management.io/v1beta2
kind: ManagedClusterSetBinding
metadata:
  name: global
  namespace: default
spec:
  clusterSet: global
```

Apply the binding to the hub:

```bash
kubectl --context kind-hub apply -f managedclustersetbinding.yaml
```

Without the required binding, the Placement may report `NoManagedClusterSetBindings` and fail to select managed clusters.

## 3. Build and Install the OCM Add-On Skill

Clone the demonstration repository if it is not already available:

```bash
git clone https://github.com/augustrh/kubeconSLC26.git
cd kubeconSLC26
```

Build the Agent Skill package:

```bash
make skill
```

Install it into Claude Code:

```bash
mkdir -p ~/.claude/skills
cp -R dist/ocm-addon-skill ~/.claude/skills/
```

Restart Claude Code so that it discovers the installed skill.

Verify that `ocm-addon-skill` appears in the available skills.

## 4. Generate the OCM Add-On Manifests

Use the Node Exporter DaemonSet example provided by the repository:

`examples/node-exporter-daemonset.yaml`

Launch Claude Code from a separate working directory and invoke the installed skill.

Example instruction:

> Use the installed ocm-addon-skill to convert the Node Exporter DaemonSet into an OCM add-on. Generate all four manifests in quiet mode inside the ocm-addon-output directory. Do not apply resources to any Kubernetes cluster.

The skill should generate four files:

| File | Kubernetes resource | Purpose |
|---|---|---|
| `01-addon-template.yaml` | AddOnTemplate | Defines the workload and deployment template |
| `02-addon-deployment-config.yaml` | AddOnDeploymentConfig | Supplies configuration values |
| `03-cluster-management-addon.yaml` | ClusterManagementAddOn | Registers the add-on and its installation strategy |
| `04-placement.yaml` | Placement | Selects the managed clusters |

Review the generated manifests before deployment.

## 5. Validate the Generated Manifests

Perform strict server-side validation against the existing OCM hub:

```bash
kubectl --context kind-hub apply \
  --dry-run=server \
  --validate=strict \
  -f ./ocm-addon-output/
```

This validates the manifests against the Kubernetes API server without persisting the resources.

Successful validation should report each resource with `(server dry run)`.

## 6. Deploy the OCM Add-On

After reviewing the generated manifests and confirming the target Kubernetes context, apply them to the hub:

```bash
kubectl --context kind-hub apply \
  -f ./ocm-addon-output/
```

The OCM add-on management components can then distribute the workload to managed clusters selected by the Placement.

## 7. Verify the Placement Decision

Check the Placement resource:

```bash
kubectl --context kind-hub \
  -n default get placement node-exporter-placement
```

Inspect the PlacementDecisions:

```bash
kubectl --context kind-hub \
  -n default get placementdecisions
```

Confirm that the expected managed cluster has been selected.

## 8. Verify the ManagedClusterAddOn

Check the add-on status on the hub:

```bash
kubectl --context kind-hub \
  -n ocm-managed get managedclusteraddons
```

Inspect the Node Exporter add-on:

```bash
kubectl --context kind-hub \
  -n ocm-managed describe managedclusteraddon node-exporter
```

The add-on should eventually report `Available=True` after a successful rollout.

Replace `ocm-managed` with the namespace corresponding to your registered ManagedCluster.

## 9. Verify the Node Exporter Workload

Check the DaemonSet and pods on the managed cluster:

```bash
kubectl --context kind-ocm-managed \
  -n monitoring get daemonsets,pods
```

Verify that the desired Node Exporter pods are running and ready.

For a single-node Kind managed cluster, the expected DaemonSet readiness is:

`1/1 Ready`

## 10. Verify Prometheus Metrics

For the tested Kind configuration, Node Exporter uses host networking and exposes metrics on port `9100`.

Check the metrics endpoint from the managed cluster node:

```bash
docker exec ocm-managed-control-plane \
  curl -fsS http://127.0.0.1:9100/metrics
```

A successful response contains Prometheus-formatted metrics, such as `node_cpu_seconds_total`.

This confirms that Node Exporter is running and exposing monitoring data.

## Tested Environment and Results

The workflow was tested using:

| Component | Version or configuration |
|---|---|
| OCM | v1.3.1 |
| Hub cluster | Kind, Kubernetes v1.37.0 |
| Managed cluster | Kind, Kubernetes v1.36.4 |
| Agent environment | Claude Code with installed `ocm-addon-skill` |
| Workload | Prometheus Node Exporter v1.12.1 |

The following results were observed:

- The packaged Agent Skill was installed and discovered successfully.
- The skill generated four OCM add-on manifests independently of the original repository.
- The generated manifests passed strict server-side validation.
- The newly generated manifests differed from previously deployed manifests only in an image-string quotation and descriptive metadata.
- The earlier deployment successfully selected the `ocm-managed` cluster through Placement.
- The ManagedClusterAddOn reported `Available=True`.
- The Node Exporter DaemonSet reached `1/1 Ready`.
- The Prometheus metrics endpoint responded successfully.

**Validation scope:** The independently generated manifests were validated against the hub but were not applied again. The successful runtime deployment was verified using the earlier, functionally equivalent manifest bundle.

## Safety Considerations

When working with existing OCM environments:

- Always specify Kubernetes contexts explicitly.
- Review generated manifests before applying them.
- Use server-side dry-run validation before deployment.
- Do not execute `make setup-env` without reviewing its cluster initialization behavior.
- Avoid `make reset` unless intentionally removing add-on resources.
- Avoid `make clean` because it can delete the existing Kind hub cluster.
- Preserve existing cluster resources and configurations during documentation and validation activities.

## Conclusion

This workflow demonstrates how the OCM Add-On Skill can be used with an existing OCM environment.

It allows users to generate, validate, deploy, and verify OCM add-on resources without requiring a new demonstration cluster setup.

The approach is useful for contributors, developers, and platform engineers who want to experiment with AI-assisted OCM add-on generation while preserving their existing Kubernetes infrastructure.

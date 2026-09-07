# OCM Add-On Skill (`ocm-addon-skill`)

`ocm-addon-skill` is an agentic skill designed for Claude CLI. It transforms standard single-cluster Kubernetes manifests into declaratively managed Open Cluster Management (OCM) Add-On bundles ready for multi-cluster fleet deployment.

## Architecture & Mental Model

The skill generates four core OCM resources — **three objects, one placement, and the hub does the rest:**
1. `AddOnTemplate`: *What to ship.* Wraps the workload manifests, with bare `{{VARIABLE}}` placeholders resolved from the deployment config.
2. `AddOnDeploymentConfig`: *Per-cluster knobs.* Fills the placeholders (image tag, log level, node placement) so one template can vary per cluster.
3. `ClusterManagementAddOn`: *Register + roll out.* Registers the add-on with the hub and wires both configs; its `installStrategy` points at a Placement.
4. `Placement`: *Which clusters — the payoff.* Selects the target fleet (`cluster.open-cluster-management.io/v1beta1`); referenced by the add-on's `installStrategy`. **Not** a Governance `PlacementBinding`.

## Quickstart

1. **Spin up local multi-cluster environment (Hub + 2 Managed Clusters):**
   ```bash
   make setup-env
   ```

2. **Run the Claude CLI Skill against a sample workload:**
   ```bash
   make demo
   ```

3. **Deploy the scaffolded Add-On to the Hub:**
   ```bash
   kubectl apply -f ./ocm-addon-output/
   ```

4. **Verify rollout across all managed clusters:**
   ```bash
   kubectl get managedclusteraddons -A
   ```

# OCM Add-On Skill (`ocm-addon-skill`)

`ocm-addon-skill` is an agentic skill designed for Claude CLI. It transforms standard single-cluster Kubernetes manifests into declaratively managed Open Cluster Management (OCM) Add-On bundles ready for multi-cluster fleet deployment.

The worked example **deploys [Prometheus node-exporter](https://github.com/prometheus/node_exporter) as an OCM add-on** — taking the DaemonSet you'd normally run on one cluster and rolling it out to every node of every cluster in the fleet, from a single apply on the hub. node-exporter exposes hardware and kernel metrics (`:9100/metrics`) for Prometheus to scrape; it's a workload most Kubernetes users already run, which makes it a clean stand-in for "any single-cluster agent." Swap in your own `Deployment` or `DaemonSet` and the skill works the same way.

## Architecture & Mental Model

The skill generates four core OCM resources — **three objects, one placement, and the hub does the rest:**
1. `AddOnTemplate`: *What to ship.* Wraps the workload manifests, with bare `{{VARIABLE}}` placeholders resolved from the deployment config.
2. `AddOnDeploymentConfig`: *Per-cluster knobs.* Fills the placeholders (image tag, log level, node placement) so one template can vary per cluster.
3. `ClusterManagementAddOn`: *Register + roll out.* Registers the add-on with the hub and wires both configs; its `installStrategy` points at a Placement.
4. `Placement`: *Which clusters — the payoff.* Selects the target fleet (`cluster.open-cluster-management.io/v1beta1`); referenced by the add-on's `installStrategy`. **Not** a Governance `PlacementBinding`.

## Pre-demo flow (stage prep)

The live talk is a 5-min lightning slot: the clusters are **pre-provisioned**, and
the only thing you do on stage is run the skill → apply → watch it light up. Get to
"ready to demo" *before* you present.

**Once, ahead of the session (slow, needs Docker + a `sudo` prompt for clusteradm):**

```bash
make setup-env      # kind hub + 2 spokes, joined & accepted, 'global' set bound to 'default'
```

Confirm both spokes are healthy before you rely on it:

```bash
kubectl --context kind-hub get managedcluster    # both: JOINED=True, AVAILABLE=True
```

**Optional but recommended — prove the live skill still matches the fallback:**

```bash
make verify         # runs the skill (--quiet) and diffs its output against break-glass/
```

**Right before you go on (fast — returns to a clean slate, clusters stay up):**

```bash
make reset          # removes any deployed add-on so the demo starts from nothing
```

Now you're staged: clusters up, nothing deployed. Keep [`docs/rollout-stage-notes.md`](docs/rollout-stage-notes.md)
(the "meanwhile, the hub is doing the work" diagram + talk-track) on screen for the
~30–90s rollout gap.

**Rehearsal loop** (repeat as often as you like without rebuilding clusters):

```bash
kubectl apply -f ./break-glass/          # deploy
kubectl get managedclusteraddon -A -w    # watch AVAILABLE flip to True on both
make reset                               # tear the add-on back down, ready for the next run
```

**Teardown when you're completely done:** `make clean` (deletes the kind clusters).

> 🧯 **Break glass:** [`break-glass/`](break-glass/README.md) holds a known-good bundle. `make demo` writes its live output to `ocm-addon-output/` and never touches it, so it's always a safe fallback: `kubectl apply -f ./break-glass/`.

## Quickstart

> New to OCM add-ons? See **[WALKTHROUGH.md](WALKTHROUGH.md)** for a step-by-step tour of what each command below does behind the scenes.

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
   > 🧯 **Demo emergency?** A known-good copy of this bundle lives in [`break-glass/`](break-glass/README.md). If the live skill run misbehaves, `kubectl apply -f ./break-glass/` instead.

4. **Verify rollout across all managed clusters:**
   ```bash
   kubectl get managedclusteraddons -A
   ```

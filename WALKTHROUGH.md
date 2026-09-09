# Quickstart Walkthrough — What Actually Happens

A step-by-step tour of the [README](README.md) quickstart commands, and what each one does *behind the scenes*. If you're new to OCM add-ons, read this alongside running the commands. The quickstart is three commands — `make setup-env`, `make demo`, `make showtime` — but that last one bundles two distinct phases (apply, then watch the rollout), so this tour breaks them out as Step 3 and Step 4.

**What this demo does:** it **deploys [Prometheus node-exporter](https://github.com/prometheus/node_exporter) as an OCM add-on.** node-exporter is a small, widely-used agent that exposes a host's hardware and kernel metrics (CPU, memory, disk, network) at `:9100/metrics` for Prometheus to scrape. It normally runs as a DaemonSet — one pod per node — with host access so it can read the real host. On one cluster that's trivial; the *real problem* is running it on every node of *every* cluster in a fleet, kept consistent and upgradable. That's exactly what turning it into an add-on solves. node-exporter is just the concrete payload — swap in any `Deployment` or `DaemonSet` and the flow is identical.

**The through-line:** step 1 is plumbing (hub + spokes + the one binding that makes placement work), step 2 is authoring (four files, no cluster touched), step 3 is a single hub-side apply, and step 4 is watching the hub fan it out. Steps 3 and 4 are both run by one command — `make showtime` — which applies the bundle and then watches the rollout to completion. The four objects map cleanly to **what to ship → how it varies → register + roll out → which clusters.**

---

## Step 1 — `make setup-env`

**What you type:** `make setup-env` → runs `./hack/setup-env.sh $(NUM_CLUSTERS)` (the argument = number of spokes, default `2`). Change the fleet size with `make setup-env NUM_CLUSTERS=3`; `make clean` honors it too, and every other command auto-discovers the spokes from the hub.

**What happens behind the scenes:**

1. **Hub cluster comes up.** `kind create cluster --name hub` spins a single-node Kubernetes cluster in Docker. This is your control plane — the "hub" in OCM terms.
2. **`clusteradm` gets installed** if it's missing (curl'd from the OCM repo).
3. **`clusteradm init --wait`** turns that plain kind cluster into an OCM hub. Behind the scenes this installs the OCM hub components — the `cluster-manager` operator and the registration/placement/addon controllers — and waits for them to be ready. This is what makes the hub able to accept spokes and run add-ons.
4. **A join token is minted.** `clusteradm get token` produces the `clusteradm join ...` command (token + hub API endpoint) that a spoke needs to register back.
5. **The loop runs twice** (`cluster-1`, `cluster-2`):
   - `kind create cluster` makes the spoke.
   - `clusteradm join ... --force-internal-endpoint-lookup` runs *against the spoke* — it installs the OCM **klusterlet** agent there and points it at the hub. `--force-internal-endpoint-lookup` matters for kind specifically: the clusters talk over Docker's internal network, so the agent has to use the internal hub address, not localhost.
   - Back on the hub, `clusteradm accept --clusters cluster-N` approves the spoke's certificate signing request. This is a **two-way handshake**: the spoke asks to join, the hub explicitly accepts. Until you accept, the cluster sits in a pending/unapproved state. After acceptance, a `ManagedCluster` object exists on the hub for each spoke.
6. **The critical binding step.** The script creates a `ManagedClusterSetBinding` for the `global` set in the `default` namespace.

   Here's the *why*: OCM's `DefaultClusterSet` feature gate (on by default) auto-creates two ManagedClusterSets — `default` and `global` — and every managed cluster lands in `global` automatically. **But** a `Placement` can only "see" clusters from ManagedClusterSets that are *bound into the Placement's own namespace*. Upstream OCM does **not** pre-bind `global` anywhere. So without this binding, your Placement in `default` would match **zero clusters** and the add-on would silently roll out to nothing — the classic demo-killer. This one object is what lets the Placement in step 3 actually resolve to your two spokes.

   > **RHACM note:** RHACM ships a pre-bound `open-cluster-management-global-set` namespace, which is why this trips people up — that's a RHACM convenience that does **not** exist upstream. Don't rely on it here.
7. **Sanity checks** print: it asserts `global` exists (fails loud if the feature gate is off), then lists your `managedclusters` and `managedclusterset`.

**End state:** a hub + 2 registered/accepted spokes, all in the `global` set, with `global` bound into `default`. Nothing about your workload yet — this is pure plumbing.

---

## Step 2 — `make demo`

**What you type:** `make demo` → runs Claude CLI with a prompt telling it to use `SKILL.md` to convert `./examples/node-exporter-daemonset.yaml` into an add-on, interactive presenter-paced, output to `./ocm-addon-output`.

**What happens behind the scenes:**

This step **touches no cluster.** It's pure authoring. The skill reads your single-cluster DaemonSet and emits the four OCM manifests into `ocm-addon-output/`, one object per turn in presenter-paced mode (it explains each, prints the YAML, then waits for you to say "next" — that's the stage-timing control). The four it produces:

- **`01-addon-template.yaml` (AddOnTemplate) — *what to ship.*** Your node-exporter DaemonSet, verbatim, wrapped in `spec.agentSpec.workload.manifests`, plus a `monitoring` Namespace. The only edits to your original YAML are two placeholders: `{{IMAGE_TAG}}` and `{{LOG_LEVEL}}`. These are **bare double-brace** template vars — *not* Go dotted-paths. That distinction is a silent-failure trap: `{{ .AddOnDeploymentConfig.spec... }}` would never resolve.
- **`02-addon-deployment-config.yaml` (AddOnDeploymentConfig) — *per-cluster knobs.*** Supplies the values for those placeholders (`IMAGE_TAG=v1.12.1`, `LOG_LEVEL=info`) via `customizedVariables`. This is the "one template, every cluster can differ" object.
- **`03-cluster-management-addon.yaml` (ClusterManagementAddOn) — *register + roll out.*** Carries the required `addon.open-cluster-management.io/lifecycle: "addon-manager"` annotation (without it the addon-manager won't own the add-on), lists both configs in `supportedConfigs`, and — the payoff wiring — sets `installStrategy.type: Placements` pointing at the `select-all` Placement in `default`.
- **`04-placement.yaml` (Placement) — *which clusters.*** `spec.clusterSets: [global]`, no predicates = select everything.

There's no controller involved yet — these are just files on disk. A known-good copy of this bundle is committed under `break-glass/` (see its README), so if the live skill run ever misbehaves on stage you can fall back to `kubectl apply -f ./break-glass/`. `make demo` writes to `ocm-addon-output/` and never touches `break-glass/`.

---

## Step 3 — `make showtime` (the apply phase)

**What you type:** `make showtime` → runs [`hack/showtime.sh`](hack/showtime.sh), which first applies all four YAMLs **to the hub** (`kubectl apply -f ./ocm-addon-output/`). Don't run the raw `kubectl apply`/`get -w` commands on stage — `showtime` wraps them so nothing hangs and you're not juggling terminals. (For a real emergency, `make showtime-glass` does the same against the `break-glass/` bundle.)

**What happens behind the scenes — this is where the hub takes over:**

1. All four objects are created on the hub. Nothing is on the spokes yet.
2. The **addon-manager** controller (running on the hub since `clusteradm init`) notices the `ClusterManagementAddOn` — because of the `lifecycle: addon-manager` annotation, it takes ownership.
3. It reads `installStrategy` → finds the `select-all` **Placement**.
4. The **placement controller** evaluates that Placement: `global` set is bound into `default` (thanks to step 1), so it resolves to `cluster-1` and `cluster-2`. It writes a `PlacementDecision` listing them.
5. For **each** selected cluster, the addon-manager creates a `ManagedClusterAddOn` object in that cluster's namespace on the hub. This is the per-cluster "install me here" record.
6. It then **renders the AddOnTemplate**: substitutes `{{IMAGE_TAG}}`/`{{LOG_LEVEL}}` from the AddOnDeploymentConfig, producing concrete manifests for each cluster.
7. The rendered manifests are **delivered to each spoke via a `ManifestWork`** (OCM's mechanism for shipping resources hub→spoke). The klusterlet agent on each spoke picks up its ManifestWork and applies it locally — creating the `monitoring` namespace and the node-exporter DaemonSet on that cluster.
8. The klusterlet **reports status back** to the hub. Because node-exporter is a DaemonSet (one of the two health-gated kinds, alongside Deployment), the add-on framework watches its rollout health and feeds that into the add-on's `Available` condition.

From one `kubectl apply` on the hub, the hub fanned the workload out to every matching spoke — *"one placement, the hub does the rest."*

---

## Step 4 — `make showtime` (the watch phase)

**What you type:** nothing new — the same `make showtime` from Step 3 now watches the rollout. After the apply, `hack/showtime.sh` live-refreshes `kubectl get managedclusteraddon -A` and the per-spoke pods until it's done, then **holds on the finished screen** (refreshing in place) until you press **Ctrl-C** — no hanging `-w`, and nothing scrolls off screen on stage. During the ~75–85s rollout it also prints the "meanwhile, the hub is doing the work" diagram under the live status so the audience can follow along; for a second-screen version of that diagram, `make diagram` opens a clean HTML render (source: [`docs/rollout-diagram.txt`](docs/rollout-diagram.txt), with a paced ~80s talk-track in [`docs/rollout-stage-notes.md`](docs/rollout-stage-notes.md)).

**What happens behind the scenes:**

`showtime` is reading back the per-cluster records from step 3.5. You'll see a `node-exporter` add-on in each spoke's namespace (`cluster-1`, `cluster-2`), and you watch the **`AVAILABLE`** column flip to `True` as each klusterlet finishes applying the DaemonSet. But the add-on's `Available` condition flips `True` when the ManifestWork is *applied*, a moment **before** the pods finish starting — so `showtime` also gates on the real signal: node-exporter pods actually `Ready` on every spoke. Only when both are true (Available fleet-wide **and** pods Ready per spoke) does it print the final per-cluster pod list and stop. That's the demo's money shot — visible proof the fleet rollout worked.

If you'd rather see it by hand, this is what those last steps are:

```bash
kubectl get managedclusteraddon -A                               # AVAILABLE True fleet-wide
kubectl --context kind-cluster-1 get pods -n monitoring -o wide   # the actual pods, on a spoke
```

The workload you started with is now on every node of every cluster, delivered by the hub — from one apply.

---

## Undeploy — `make reset` (between rehearsals)

**What you type:** `make reset` — removes the add-on but keeps the clusters, so you're back at "ready to demo" without rebuilding the fleet.

**What happens behind the scenes:**

1. It deletes the add-on objects **on the hub by kind and name** — `ClusterManagementAddOn`, `AddOnTemplate`, `AddOnDeploymentConfig`, and every `Placement` in `default`. Deleting by name (rather than `kubectl delete -f` a bundle dir) matters: the live skill run may have named its Placement something different from the fallback, so name-based deletion cleans up whichever one is there and never leaves an orphan.
2. Deleting the `ClusterManagementAddOn` triggers the reverse of the rollout: the addon-manager removes each per-cluster `ManagedClusterAddOn`, which deletes its `ManifestWork`, which tells each klusterlet to **remove the node-exporter DaemonSet from its spoke**. This is OCM's garbage collection — the same hub→spoke channel, running backwards.
3. That spoke cleanup is **asynchronous**: the hub-side delete returns immediately, but the pods take a beat to terminate. So reset then **waits** (via `hack/wait-spokes-clean.sh`) until the `monitoring` namespace is empty on every spoke, capped at 60s. When reset returns, the fleet is genuinely clean — not just the hub.

**End state:** hub + spokes still up and registered, no add-on anywhere. Run `make demo` → apply → watch again as many times as you like. (Full teardown of the kind clusters is `make clean`.)

---

## The four objects at a glance

| # | Object | Role | One-liner |
|---|--------|------|-----------|
| 1 | `AddOnTemplate` | What to ship | Your workload as cargo the hub knows how to ship |
| 2 | `AddOnDeploymentConfig` | How it varies | Per-cluster knobs fill the `{{VARIABLE}}` placeholders |
| 3 | `ClusterManagementAddOn` | Register + roll out | `installStrategy` points at a Placement |
| 4 | `Placement` | Which clusters | Select the fleet — the payoff |

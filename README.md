# OCM Add-On Skill (`ocm-addon-skill`)

`ocm-addon-skill` is an agentic skill designed for Claude CLI. It transforms standard single-cluster Kubernetes manifests into declaratively managed Open Cluster Management (OCM) Add-On bundles ready for multi-cluster fleet deployment.

The worked example **deploys [Prometheus node-exporter](https://github.com/prometheus/node_exporter) as an OCM add-on** — taking the DaemonSet you'd normally run on one cluster and rolling it out to every node of every cluster in the fleet, from a single apply on the hub. node-exporter exposes hardware and kernel metrics (`:9100/metrics`) for Prometheus to scrape; it's a workload most Kubernetes users already run, which makes it a clean stand-in for "any single-cluster agent." Swap in your own `Deployment` or `DaemonSet` and the skill works the same way.

The work is planned to be presneted as a Lightning Talk at KubeCon NA 2026. The core of this work is a **DEMO** and is not intended for any production use. Whilst there is a verb to create a standalone skill the core use here is as a demo to introduce others to OCM add-ons and demonestrate quickly, but also indepdently after the talk, the HOW of doing this.

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
make setup-env      # kind hub + 2 spokes, joined & accepted, 'global' bound to 'default', node-exporter image pre-pulled onto each spoke
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

`make reset` deletes the add-on objects on the hub by kind/name (so it works no
matter what the live run named its Placement) and then **waits until node-exporter
is actually gone from every spoke** before returning — the hub-side delete finishes
first, but the workload comes off the spokes a beat later (ManifestWork GC). When
reset returns, you're genuinely at a clean slate.

Now you're staged: clusters up, nothing deployed. For the ~75–85s rollout gap, keep
[`docs/rollout-stage-notes.md`](docs/rollout-stage-notes.md) (the "meanwhile, the hub
is doing the work" diagram + a paced ~80s talk-track) handy. To put the diagram on a
second screen as a clean, projector-friendly page:

```bash
make diagram        # regenerate + open docs/rollout-diagram.html in your browser
```

The diagram has one source of truth — [`docs/rollout-diagram.txt`](docs/rollout-diagram.txt) —
which `make showtime` prints live, the stage notes embed, and `make diagram` renders.
Edit that one file and all three stay in sync. For a static image (slides), run
`bash ./hack/render-diagram.sh --png` to also write `docs/rollout-diagram.png`.

**Rehearsal loop** (repeat as often as you like without rebuilding clusters):

```bash
make demo                # generate the bundle (interactive, presenter-paced)
make showtime            # apply + watch until Available + show pods per spoke (holds until Ctrl-C)
make reset               # tear the add-on back down + wait for spokes to drain, ready for the next run
```

`make showtime` runs the three payoff steps as one calm flow (no hanging `kubectl … -w`).
For a real on-stage emergency, `make showtime-glass` runs the same flow against the
known-good `break-glass/` bundle.

### `reset` vs `clean` — two scopes of teardown

| Command | What it removes | What survives | When to use |
| ------- | --------------- | ------------- | ----------- |
| `make reset` | Just the add-on: the objects on the hub **and** the workload off the spokes (waits until `monitoring` is empty on every spoke). Bundle-agnostic — deletes by kind/name, so no orphaned Placement. | The kind clusters stay up. | **Between rehearsals** — back to "ready to demo" in seconds without rebuilding. |
| `make clean` | The **kind clusters entirely** (`hub`, `cluster-1`, `cluster-2`) plus the live `ocm-addon-output/` files. | Nothing (the host's cached image persists — that's intentional, it makes the next build fast). | **Starting over from scratch**, or when you're completely done. |

**Full from-scratch rebuild:**

```bash
make clean          # delete all three kind clusters + live output
make setup-env      # rebuild hub + 2 spokes, join/accept, bind 'global', pre-pull the image
```

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

3. **Deploy the scaffolded Add-On and watch it roll out — one command:**
   ```bash
   make showtime
   ```
   `make showtime` runs all three payoff steps as one calm flow: applies
   `./ocm-addon-output/` to the hub, live-refreshes the rollout until every add-on is
   `Available` **and** node-exporter pods are actually `Ready` on each spoke, prints
   the pods per cluster, then **holds on the finished screen** (refreshing in place)
   until you press **Ctrl-C** — no hanging `kubectl … -w`, nothing scrolls away on stage.
   > 🧯 **Demo emergency?** If the live skill run misbehaves, `make showtime-glass`
   > runs the exact same flow against the known-good [`break-glass/`](break-glass/README.md) bundle.

   <details><summary>What <code>make showtime</code> does under the hood (if you'd rather run it by hand)</summary>

   ```bash
   kubectl apply -f ./ocm-addon-output/          # apply the 4 objects to the hub
   kubectl get managedclusteraddons -A           # watch AVAILABLE flip to True fleet-wide
   kubectl --context kind-cluster-1 get pods -n monitoring -o wide   # the pods, on a spoke
   ```
   </details>

## Take the skill with you (`make skill`)

The demo drives `SKILL.md` directly, but the skill also stands on its own. `make skill`
packages it as a self-contained, installable [Agent Skill](https://code.claude.com/docs/en/skills)
under `dist/` (gitignored) — **without changing anything in this repo**: it reads
`SKILL.md` + `examples/` and writes a copy with the required frontmatter *prepended in
the generated package only*.

```bash
make skill                          # build dist/ocm-addon-skill/ (SKILL.md + examples/ + install README)
bash ./hack/build-skill.sh --zip    # also write dist/ocm-addon-skill.zip to share
```

Then install and try it in any project:

```bash
cp -R dist/ocm-addon-skill ~/.claude/skills/   # then restart Claude Code
# ...and just ask: "turn examples/node-exporter-daemonset.yaml into an OCM add-on"
```

The package is fully self-contained, so you can also lift `dist/ocm-addon-skill/`
straight into an `OCM/skills/`-style repo.

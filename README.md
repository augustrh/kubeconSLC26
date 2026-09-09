# OCM Add-On Skill (`ocm-addon-skill`)

`ocm-addon-skill` is an agentic skill designed for Claude CLI. It transforms standard single-cluster Kubernetes manifests into declaratively managed Open Cluster Management (OCM) Add-On bundles ready for multi-cluster fleet deployment.

The worked example **deploys [Prometheus node-exporter](https://github.com/prometheus/node_exporter) as an OCM add-on** — taking the DaemonSet you'd normally run on one cluster and rolling it out to every node of every cluster in the fleet, from a single apply on the hub. node-exporter exposes hardware and kernel metrics (`:9100/metrics`) for Prometheus to scrape; it's a workload most Kubernetes users already run, which makes it a clean stand-in for "any single-cluster agent." Swap in your own `Deployment` or `DaemonSet` and the skill works the same way.

## What this is and what this is not (please read!)
The work is planned to be presented as a Lightning Talk at KubeCon NA 2026. The core of this work is a **DEMO** and is not intended for any production use. Whilst there is a verb to create a standalone skill the core use here is as a demo to introduce others to OCM add-ons and demonestrate quickly, but also indepdently after the talk, the HOW of doing this.

## Architecture & Mental Model

The skill generates four core OCM resources — **three objects, one placement, and the hub does the rest:**
1. `AddOnTemplate`: *What to ship.* Wraps the workload manifests, with bare `{{VARIABLE}}` placeholders resolved from the deployment config.
2. `AddOnDeploymentConfig`: *Per-cluster knobs.* Fills the placeholders (image tag, log level, node placement) so one template can vary per cluster.
3. `ClusterManagementAddOn`: *Register + roll out.* Registers the add-on with the hub and wires both configs; its `installStrategy` points at a Placement.
4. `Placement`: *Which clusters — the payoff.* Selects the target fleet (`cluster.open-cluster-management.io/v1beta1`); referenced by the add-on's `installStrategy`. **Not** a Governance `PlacementBinding`.

## Quickstart

> New to OCM add-ons? **[WALKTHROUGH.md](WALKTHROUGH.md)** tours what each command below does behind the scenes.

```bash
make setup-env      # 1. one-time (slow): local fleet — kind hub + 2 spokes
make demo           # 2. run the skill — scaffold the add-on from a sample workload
make showtime       # 3. apply it + watch it roll out fleet-wide (Ctrl-C when done)
```

That's the whole loop: `setup-env` is a one-time setup step, then `demo` → `showtime`
is the demo itself. Everything else is in **[Commands](#commands)**; if you're
presenting, see **[Running the live talk](#running-the-live-talk)**.

## Commands

| Command | What it does |
| ------- | ------------ |
| `make setup-env` | One-time: build the local fleet (kind hub + N spokes). |
| `make demo` | Run the skill — scaffold the four add-on objects from a sample workload. |
| `make showtime` | Apply the bundle + watch it roll out fleet-wide (holds until Ctrl-C). |
| `make showtime-glass` | Like `showtime`, but deploys the known-good `break-glass/` bundle. |
| `make reset` | Remove the add-on, keep the clusters — use between rehearsals. |
| `make clean` | Delete the demo's kind clusters + live output — start over. |
| `make verify` | Run the skill headless and diff its output against `break-glass/`. |
| `make diagram` | Open the rollout diagram as a clean HTML page. |
| `make skill` | Package the skill as a standalone, installable Agent Skill. |

- **Fleet size** defaults to 2 — change it with `NUM_CLUSTERS`, e.g. `make setup-env NUM_CLUSTERS=3`.
- **`reset` vs `clean`:** `reset` keeps the clusters up (fast, between rehearsals); `clean` deletes them (start fresh, then `make setup-env` to rebuild).

## Running the live talk

The talk is a 5-minute lightning slot: the clusters are **pre-provisioned**, so on
stage you only run the skill → apply → watch it light up. Get to "ready to demo"
*before* you present.

**Once, ahead of the session** (slow; needs Docker, and `clusteradm` may prompt for `sudo`):

```bash
make setup-env
kubectl --context kind-hub get managedcluster    # confirm each spoke: JOINED=True, AVAILABLE=True
```

**Right before you go on** (fast — clusters stay up):

```bash
make reset          # back to a clean slate: clusters up, nothing deployed
```

`make reset` waits until node-exporter is actually gone from every spoke before
returning (the hub-side delete finishes first; the workload comes off the spokes a
beat later via ManifestWork GC), so you're genuinely at zero.

**The live loop** (rehearse it as often as you like — no cluster rebuild):

```bash
make demo           # scaffold the bundle (interactive, presenter-paced)
make showtime       # apply + watch the rollout, holds until Ctrl-C
make reset          # tear it back down, ready for the next run
```

During the **~75–85s rollout gap**, narrate from
[`docs/rollout-stage-notes.md`](docs/rollout-stage-notes.md) (the diagram + a paced
~80s talk-track). Put the diagram on a second screen with `make diagram`; it and the
live `showtime` screen share one source, [`docs/rollout-diagram.txt`](docs/rollout-diagram.txt).
For a slide image, run `bash ./hack/render-diagram.sh --png`.

> 🧯 **Break glass:** [`break-glass/`](break-glass/README.md) is a known-good bundle
> that `make demo` never touches. If the live run misbehaves, `make showtime-glass`
> deploys it instead. (Optional pre-flight: `make verify` proves the live skill still
> matches this fallback.)

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

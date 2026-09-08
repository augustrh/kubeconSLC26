# Demo presenter guide — what to say at each step

A cue card for running the live `make demo` (interactive, presenter-paced). The
skill scaffolds **one object per turn** and waits for you to say "next" — so each
section below is one beat. Keep it spoken and short; this is a 5-min lightning slot.

**Through-line to keep repeating:** *three objects, one placement, and the hub does the rest.*

- Object order: AddOnTemplate → AddOnDeploymentConfig → ClusterManagementAddOn → Placement.
- Companion docs: [WALKTHROUGH.md](../WALKTHROUGH.md) (behind-the-scenes), [rollout-stage-notes.md](rollout-stage-notes.md) (the "meanwhile" diagram for the rollout wait).

---

## Step 1 — `AddOnTemplate` ("what to ship")

**What Claude puts on screen:** an `AddOnTemplate` named `node-exporter`. Your DaemonSet dropped in verbatim under `agentSpec.workload.manifests`, a `monitoring` Namespace added ahead of it, and just two edits: `{{IMAGE_TAG}}` and `{{LOG_LEVEL}}`.

**Say this:** "This is the same node-exporter DaemonSet you'd run on one cluster — I didn't rewrite it, I *wrapped* it. It's now cargo the hub knows how to ship. The only changes are two placeholders, image tag and log level, so one template can flex per cluster. And notice what's *not* here: no `spec.registration`, because node-exporter just reads the local host — it never phones the hub, so it needs no hub credential."

**If asked / go deeper:**
- Placeholders are **bare** `{{IMAGE_TAG}}` — *not* a Go dotted path like `{{ .AddOnDeploymentConfig… }}`, which silently fails to resolve. (This is a common first mistake.)
- `spec.registration` is where you'd grant an agent hub access (RBAC / signers) — skipped here on purpose.
- Full mechanics: [WALKTHROUGH.md](../WALKTHROUGH.md) Step 2.

---

## Step 2 — `AddOnDeploymentConfig` ("per-cluster knobs")

**What Claude puts on screen:** an `AddOnDeploymentConfig` (in `open-cluster-management`) with two `customizedVariables` — `LOG_LEVEL=info`, `IMAGE_TAG=v1.12.1`. These are exactly what the template's `{{LOG_LEVEL}}` / `{{IMAGE_TAG}}` resolve to.

**Say this:** "Here's the dial. Same template ships everywhere — these values are what fill those two placeholders. This one is the *fleet-wide default*. And here's the part people miss: if I want one cluster to run a different image or debug logging, I don't fork the workload — I write a second config and point that one cluster's `ManagedClusterAddOn` at it. One template, many dials."

**If asked / go deeper:**
- Per-cluster override path: a cluster's `ManagedClusterAddOn.spec.configs` points at an alternate `AddOnDeploymentConfig`.
- Object 3 wires *this* config in as the `defaultConfig` — that's the link that makes it fleet-wide.
- Full mechanics: [WALKTHROUGH.md](../WALKTHROUGH.md) Step 2.

---

## Step 3 — `ClusterManagementAddOn` ("register + roll out")

**What Claude puts on screen:** the `ClusterManagementAddOn` — the registration. `supportedConfigs` names *what to ship* (the template) and *how it varies* (the deployment config); `installStrategy: Placements` hands rollout to a Placement we haven't written yet.

**Say this:** "This ties the last two objects together and registers the add-on with the hub. The magic word is `installStrategy` — it says 'wherever this placement points, install me.' Two things I want you to see: this annotation, `lifecycle: addon-manager`, is *not* optional — it's what hands the add-on to the built-in manager that actually renders the template. Leave it off and nothing installs, quietly. And notice there's no PlacementBinding anywhere — that's a different subsystem, Governance. Add-on rollout is `installStrategy → Placement`, full stop."

**If asked / go deeper:**
- Missing `lifecycle: "addon-manager"` = **silent** no-op (nothing installs, no obvious error) — the #1 gotcha.
- `supportedConfigs` must list **both** resources (`addontemplates` *and* `addondeploymentconfigs`), each with its `defaultConfig`.
- `PlacementBinding` is `policy.open-cluster-management.io` (Governance), unrelated to add-ons — a frequent confusion.
- Full mechanics: [WALKTHROUGH.md](../WALKTHROUGH.md) Step 3.

---

## Step 4 — `Placement` ("which clusters — the payoff")

**What Claude puts on screen:** a tiny `Placement` in `default` — `clusterSets: [global]`, no predicates. That's the whole file.

**Say this:** "That's it — that's the object that picks the fleet. `global` holds every managed cluster, no predicates, so this selects all of them. Want to narrow it later? Add a predicate — `region=us-west`, or dev-only — and the rollout just follows. No other file changes. One object selects the fleet, and the hub does the rest."

**If asked / go deeper:**
- Narrowing: `spec.predicates` on labels or cluster claims (e.g. `region=us-west`, `env=dev`).
- The gotcha it depends on: a Placement only sees ClusterSets *bound into its namespace*. `hack/setup-env.sh` creates the `global` `ManagedClusterSetBinding` in `default` up front. Without it, the Placement silently matches **zero** clusters (fallback YAML is in the file's trailing comment).
- Note it's `cluster.open-cluster-management.io/v1beta1` — the Placement stayed `v1beta1` even though the ClusterSet/Binding moved to `v1beta2`.
- Full mechanics: [WALKTHROUGH.md](../WALKTHROUGH.md) Step 3.

---

## The payoff (after the four objects)

**Linger on the summary table.** Claude prints a four-row table (file → kind → namespace → role). This is your best single slide — don't rush past it. Sit on it for a beat and let it land:

> "Here's the whole thing. Four files. What to ship, how it varies, register it, pick the clusters. That's the entire mental model — `AddOnTemplate`, `AddOnDeploymentConfig`, `ClusterManagementAddOn`, `Placement`. If you remember one slide from this talk, it's this one."

**Then deploy — one command, not three.** Claude ends by suggesting three commands
(apply, then `get … -w`, then per-spoke pods). Acknowledge them, but don't run them
live — the `-w` hangs forever and you'd be juggling terminals under pressure. Instead:

> "Claude even hands me the apply and verify commands. I'm going to close this session
> and run them as one script, so we can just watch it happen."

Close the Claude session, then:

```bash
make showtime          # applies ./ocm-addon-output, watches until Available, shows pods per spoke
```

`make showtime` does all three payoff steps as one calm flow: applies the bundle,
live-refreshes the rollout table until every add-on is `Available` **and** pods are
`Ready` on each spoke, prints node-exporter pods per spoke, then **holds on the
finished screen** (refreshing in place) until you press **Ctrl-C** — no hanging `-w`,
nothing scrolls away. The ~75–85s wait is OCM's reconcile floor, not image pull, so
it's steady every time — **own it as narration time.**

While it watches, narrate the rollout from [rollout-stage-notes.md](rollout-stage-notes.md).
`make showtime` prints the "meanwhile, the hub is doing the work" diagram right on the
live screen; for a clean second-screen copy, run `make diagram` (opens an HTML render).
The stage notes have a **paced ~80s talk-track** (0–10s apply → 10–25s hub picks it up
→ 25–45s fan-out + templating → 45–65s ship to spokes → 65–80s payoff) built to fill
exactly this window — walk the diagram top-to-bottom and you'll land on the payoff as
the fleet goes green.

**Say this (on apply):** "Four objects, one apply, on the hub — I never touched the
managed clusters. Watch it light up across the fleet."

**Don't be startled by Ctrl-C:** because you ran it through `make`, pressing Ctrl-C
also prints a harmless `make: *** [showtime] Interrupt` line. It's cosmetic. To avoid
it entirely, run `bash ./hack/showtime.sh` directly instead of `make showtime`.

**Emergency:** if the live bundle is bad, `make showtime-glass` runs the exact same
flow against the known-good `break-glass/` bundle.

**Close on the through-line:** *"Three objects, one placement, and the hub does the rest."*

---

## Between run-throughs (not on stage) — `make reset`

When you're rehearsing and want to go again, `make reset` puts you back to a clean
slate without rebuilding the clusters. It deletes the add-on on the hub and then
**waits until node-exporter is actually gone from every spoke** before it returns —
so when the prompt comes back, you're genuinely at zero and the next `make demo` /
`make showtime` starts clean. (It's also robust to whatever the live run named its
Placement, so nothing gets left behind between takes.) You'll see it print
`… N pod(s) still terminating` a couple of times, then `✅ spokes clean`. Full
teardown of the clusters is `make clean`.

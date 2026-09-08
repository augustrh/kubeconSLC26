# "Meanwhile, the hub is doing the work" — rollout stage notes

The gap between the apply and both clusters showing `AVAILABLE=True` is a reliable
**~75–85s** (measured: `time make showtime` ≈ 1:23). It's *not* image-pull time —
`setup-env` pre-pulls the image, and the run is only ~9% CPU. It's OCM's add-on
health-reconcile floor: the hub polling and re-checking conditions on its own
schedule. You can't hurry it, so **own it** — it's your narration window, not dead
air. `make showtime` holds on the live screen (status + this diagram) the whole
time, then stays on the finished screen until you Ctrl-C. Narrate the diagram.

Use the paced script below (**"Filling the ~80s"**) as your primary track; the
condition-triggered version further down is the fallback if the reconcile runs
fast or slow.

---

## The slide: what happens after one apply

This is the **canonical diagram** — the exact same text that `hack/showtime.sh`
prints on the live screen and that `docs/rollout-diagram.html` renders as a clean
pop-up. The single source of truth is [`rollout-diagram.txt`](rollout-diagram.txt);
edit that one file and all three stay in sync. Keep the block below identical to it.

```
─────────────────────────  meanwhile, the hub is doing the work  ─────────────────────────


     YOU  ──▶  kubectl apply      (4 objects, once, on the HUB)
      │
      ▼
     ClusterManagementAddOn  ──(installStrategy)──▶  Placement  ──▶  PlacementDecision
      │   addon-manager owns it                                        [ the fleet ]
      ▼
     ManagedClusterAddOn      (one per selected cluster)
      │   renders AddOnTemplate + vars   ({{IMAGE_TAG}}, {{LOG_LEVEL}})
      ▼
     ManifestWork  ──▶  shipped down to each spoke
      │
      ▼
     ┌──── spoke ────┐    klusterlet applies Namespace + DaemonSet;
     │ node-exporter │    pods start, one per node, report healthy  ──▶  back to hub
     └───────────────┘
      │
      ▼
     AVAILABLE = True      (per cluster)


──────────────────────────────────────────────────────────────────────────────────────
```

---

## Filling the ~80s — a paced walk down the diagram

This is a **time-driven** script (not condition-driven): you say these beats in
order, top-to-bottom of the diagram, whether or not the watch has flipped yet.
It's built to *fill* the full reconcile window calmly. Point at each diagram
region as you go. Total ≈ 80s; if you run out of diagram before the fleet goes
green, just slow down on the last beat — showtime is holding, nothing scrolls away.

**0–10s — the apply (top of the diagram: `YOU → kubectl apply`).**
"Everything I just did was one `kubectl apply`, once, to the **hub**. Four objects.
I did not `ssh` anywhere, I did not touch the managed clusters. From here on, I'm
just watching — the hub is doing all the work."

**10–25s — the hub picks it up (`ClusterManagementAddOn → Placement → PlacementDecision`).**
"On the hub, the add-on manager sees my ClusterManagementAddOn. Its install
strategy points at a **Placement** — that's the 'which clusters' object. The
Placement resolves to a PlacementDecision: the actual list of clusters in my
fleet. Right now that's two, but this is a *set*, not a hard-coded list."

**25–45s — fan-out and templating (`for EACH selected cluster → ManagedClusterAddOn → renders vars`).**
"For **each** cluster in that decision, the hub creates a ManagedClusterAddOn and
renders my AddOnTemplate — this is where the per-cluster knobs get filled in, the
image tag and the log level, from the deployment config. So one template, but each
cluster can differ. No copy-paste, no per-cluster YAML."

**45–65s — ship it down (`ships a ManifestWork → spoke → klusterlet applies`).**
"Then it ships the rendered result down to each spoke as a **ManifestWork**. The
klusterlet — the OCM agent already running on each managed cluster — pulls that
work, creates the namespace, and starts the node-exporter DaemonSet. One pod per
node. The spoke reports the pods healthy back up to the hub." *(By now the first
cluster is usually flipping green — call it out if it does: "there's the first
one.")*

**65–80s — the payoff (`AVAILABLE=True`, bottom of the diagram + the finished screen).**
"And that's the fleet. `AVAILABLE=True` on every cluster — every node of every
cluster is now running node-exporter, from that one apply. And because the target
is a *Placement*, if I add a tenth cluster tomorrow, it joins the set and the hub
does all of this again, automatically. **Three objects, one placement, and the hub
does the rest.**"

---

## Talk-track (condition-triggered fallback)

**On apply (0s):** "I applied four objects — once, to the hub. I did **not** touch
the managed clusters. Watch."

**While AVAILABLE=False / PROGRESSING (0–30s):** "The hub's add-on manager just
saw my ClusterManagementAddOn. It followed the install strategy to my Placement,
the Placement resolved to *these* clusters, and for each one the hub is rendering
my template — dropping in the per-cluster image tag and log level — and shipping
it down as a ManifestWork."

**As the first cluster flips True:** "There's the first one. The klusterlet on
that spoke pulled the work, created the namespace, started the DaemonSet, and
reported its pods healthy back to the hub."

**As the second flips True:** "And the fleet's done. One apply, on the hub. Every
node of every cluster is now running node-exporter — and if I add a tenth cluster
tomorrow, the Placement picks it up and the hub does this again, automatically."

**Payoff line:** "Three objects, one placement, and the hub does the rest."

---

## If it stalls (stage recovery)

Keep these one-liners ready; run in a second pane, narrate calmly:

- `kubectl get placementdecision -n default -o wide` — proves the fleet was selected.
- `kubectl --context kind-cluster-1 get pods -n monitoring` — proves the workload landed.
- Worst case: it's already deployed on cluster-2 (show that), and "the second one
  is just finishing its first health report" — true, and buys time.

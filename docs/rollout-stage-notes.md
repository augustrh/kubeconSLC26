# "Meanwhile, the hub is doing the work" — rollout stage notes

The gap between `kubectl apply -f ./break-glass/` and both clusters showing
`AVAILABLE=True` is ~30–90s. That's not dead air — it's the payoff. Put the
diagram below on screen and narrate the beats while the `-w` watch fills in.

---

## The slide: what happens after one apply

```
        YOU
         │  kubectl apply -f ./break-glass/   (4 objects, once, on the HUB)
         ▼
   ┌───────────────────────────── HUB ─────────────────────────────┐
   │                                                                │
   │  ClusterManagementAddOn ──(installStrategy: Placements)──▶ Placement
   │        │                                                    │  select-all
   │        │ addon-manager owns it                              │  clusterSets:[global]
   │        ▼                                                    ▼
   │  reads Placement ◀───────────────── PlacementDecision [cluster-1, cluster-2]
   │        │
   │        │ for EACH selected cluster:
   │        ▼
   │  ManagedClusterAddOn (cluster-1 ns)   ManagedClusterAddOn (cluster-2 ns)
   │        │  renders AddOnTemplate               │
   │        │  + AddOnDeploymentConfig vars         │
   │        ▼  ({{IMAGE_TAG}}, {{LOG_LEVEL}})       ▼
   │   ManifestWork ─────┐                    ManifestWork ─────┐
   └─────────────────────┼──────────────────────────────────────┼───────────┘
                         ▼                                       ▼
                 ┌──── cluster-1 ────┐                   ┌──── cluster-2 ────┐
                 │ klusterlet applies│                   │ klusterlet applies│
                 │ Namespace+DaemonSet│                  │ Namespace+DaemonSet│
                 │ node-exporter pods │                  │ node-exporter pods │
                 │ report healthy ────┼──▶ status back    │ report healthy ────┼──▶ status back
                 └───────────────────┘   to hub          └───────────────────┘   to hub
                         │                                       │
                         └────────▶ AVAILABLE=True ◀─────────────┘
```

---

## Talk-track (time it to the watch)

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

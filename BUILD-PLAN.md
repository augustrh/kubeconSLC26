# OCM Add-On Skill — Build Plan (KubeCon SLC 2026)

> **Goal:** an agentic Claude Code skill that, live on stage, turns a single-cluster controller/workload into a working OCM add-on running across the whole fleet — **explaining each object as it scaffolds it.** Talk premise: "three objects, one placement, the hub does the rest."
>
> Deliverables: (1) the **skill** (teaching + scaffolding), (2) a **reproducible demo env**, (3) a **rehearsed live flow** that actually deploys and verifies.

---

## 1. Current state (what's in the lab)

A solid v0 skeleton already exists:
- `SKILL.md` — v0 skill: converts a manifest → 4 OCM YAMLs. **Good bones, but technically inaccurate in places (see §3).**
- `hack/setup-env.sh` — kind hub + N spokes via `clusteradm init` / `join` / `accept`. Works, upstream OCM.
- `Makefile` — `setup-env`, `demo` (runs `claude --dangerously-skip-permissions`), `test-e2e`, `clean`.
- `examples/sample-deployment.yaml` — trivial alpine "sleep 3600" Deployment.
- `README.md`, `OWNERS` (augustrh). Repo: `github.com/augustrh/lab`, this skill under `lab/ocm-addon-skill`.

Assessment: the scaffold, env, and demo harness are ~70% there. The gaps are **technical correctness of the generated YAML** and **the teaching behavior the talk is actually about.**

---

## 2. Runtime assumption

**Upstream OCM** (clusteradm + kind), not RHACM — matches the existing env, the docs, and a vendor-neutral KubeCon audience. Everything below uses `addon.open-cluster-management.io/v1alpha1` and the `clusteradm` toolchain. (Flag if you'd rather target RHACM.)

---

## 3. Technical grounding & corrections (from the OCM docs)

The **AddOnTemplate-based ("no-code") add-on** is the right model. The accurate object set is:

**Object 1 — `ClusterManagementAddOn`** (hub registration + rollout)
- Needs annotation `addon.open-cluster-management.io/lifecycle: "addon-manager"`.
- `spec.supportedConfigs` references **both** `addontemplates` and `addondeploymentconfigs` (each with a `defaultConfig` name/namespace).
- `spec.installStrategy.type: Placements` → `placements: [{name, namespace}]`. **This is how it rolls out.**

**Object 2 — `AddOnTemplate`** (what to ship)
- `spec.addonName`, `spec.agentSpec.workload.manifests` (wraps the user's workload), optional `spec.registration` (hub RBAC / custom signers).

**Object 3 — `AddOnDeploymentConfig`** (per-fleet/per-cluster config)
- `spec.customizedVariables: [{name, value}]`, `spec.agentInstallNamespace`, `spec.nodePlacement`.

**Object 4 — `Placement`** (`cluster.open-cluster-management.io/v1beta1`) — selects target clusters; referenced by Object 1's installStrategy.

### ⚠️ Corrections vs. the current (Gemini) SKILL.md — these matter for a live demo
1. **Object 4 is a `Placement`, NOT a Governance `PlacementBinding`.** The current SKILL.md emits `PlacementBinding` from `policy.open-cluster-management.io` — that's the **Governance** framework, unrelated to add-ons. Add-on rollout is driven by `ClusterManagementAddOn.spec.installStrategy` → Placement. **Drop PlacementBinding entirely.**
2. **Templating syntax is bare `{{VARIABLE_NAME}}`**, resolved from `AddOnDeploymentConfig.customizedVariables`, plus built-ins like `{{CLUSTER_NAME}}` and `{{HUB_KUBECONFIG}}`. The current `{{ .AddOnDeploymentConfig.spec.customizedVariables.replicas }}` dotted Go-path is **wrong** and won't resolve.
3. **Missing the `addon-manager` lifecycle annotation** on ClusterManagementAddOn — without it the addon-manager won't own/roll out the addon.
4. **supportedConfigs must include the AddOnTemplate**, not just the AddOnDeploymentConfig.
5. **Workload health-check supports `Deployment`/`DaemonSet`** as the "crucial" agent workload — the sample Deployment is fine; other kinds (ConfigMaps etc.) can ride along in manifests but won't be health-gated.

### 🕳️ Demo-breaking gotcha to design around
A `Placement` only selects clusters from **ManagedClusterSets bound to the Placement's namespace** (via `ManagedClusterSetBinding`). A Placement in `default` will select **nothing** unless a binding exists.

**Upstream reality (verified):** the `DefaultClusterSet` feature gate (on by default) auto-creates the `default` and `global` ManagedClusterSets, but upstream OCM does **not** pre-bind `global` to any namespace. (The pre-bound `open-cluster-management-global-set` namespace is an RHACM-ism — do **not** rely on it upstream.)

**Fix (chosen):** `hack/setup-env.sh` emits a `ManagedClusterSetBinding` for `global` in the `default` namespace after the spokes join. The Placement then lives in `default`, `spec.clusterSets: [global]`, and the *live bundle stays exactly the four objects* — the binding is env plumbing, not part of the stage story. The skill still knows how to emit the binding itself if told the env lacks one. setup-env.sh also asserts the `global` set exists so a missing feature gate fails loud, not silent.

### Feature gate
`AddonManagement` must not be disabled (on by default in recent OCM / `clusteradm init`). Verify in rehearsal; add an assert to `setup-env.sh`.

---

## 4. The core redesign — a *teaching* skill (this is the talk)

The current SKILL.md says "do not add conversational text." The talk is the opposite: **explain each piece as it goes.** So the skill gains a narration/teaching mode:

- For each of the 4 objects: **(a) say what it is and why it exists** ("this is the contract that tells the hub *where* to run it"), **(b) show the YAML**, **(c) connect it to the previous object** (the through-line: template → config → registration → placement).
- End with the "one placement, the hub does the rest" payoff + the exact apply/verify commands.
- Keep a **`--quiet` / scaffold-only path** for when you just want the files (and for `make test-e2e`).
- Open design question: **interactive step-by-step (pause per object)** vs **generate-all-then-walk** — see §6.

---

## 5. Demo reliability plan

A live cluster build can't happen in the talk window. Plan:
- **Pre-provision** hub + 2 spokes before the session (`make setup-env`); the *live* part is running the skill → `kubectl apply` → `kubectl get managedclusteraddon -A` lighting up across clusters.
- **Rehearsed golden path** + a **pre-generated bundle committed under `break-glass/`** as a fallback if the live skill run misbehaves (`kubectl apply -f ./break-glass/`). `make demo` writes to `ocm-addon-output/`, so the fallback is never clobbered.
- **Assertions** in setup: managedclusters `Available`, addon-manager running, global-set binding present, feature gate on.
- A **teardown/reset** (`make clean`) and a **re-arm** script to get back to a known state between rehearsals.
- Timeboxed **rollout wait** with a visible verify (watch the addons flip to `Available`).

---

## 6. Locked decisions (answered)

1. **Talk format:** **5-min lightning.** Env pre-provisioned; live part = run skill → apply → watch it light up.
2. **Demo workload:** **recognizable real agent** → **node-exporter** (DaemonSet; "run node metrics on every node of every cluster" is the fleet story). Swappable.
3. **Skill UX:** **interactive step-by-step**, reconciled for 5 min as **presenter-paced** — one object per turn, one punchy line each, waits for "next" so August controls stage timing. A `--quiet`/all mode emits everything at once (for `test-e2e`).

**Framing note:** the abstract's "three objects, one placement binding" = `AddOnTemplate` + `AddOnDeploymentConfig` + `ClusterManagementAddOn` (three objects) + one **`Placement`**. Consider changing "placement binding" → "placement" in the abstract for accuracy.

**Teaching build order:** Template (what to ship) → DeploymentConfig (per-cluster knobs) → ClusterManagementAddOn (register + rollout) → Placement (which clusters = the payoff).

---

## 7. Proposed build phases (once §6 is answered)

- **P1 — Fix the skill's YAML correctness** (the §3 corrections) + a known-good `ocm-addon-output/` for the sample.
- **P2 — Add teaching/narration mode** (the §4 through-line) + `--quiet` path.
- **P3 — Harden the env** (global-set binding, asserts, reset script) so rollout is deterministic.
- **P4 — End-to-end rehearsal**: real deploy across 2 spokes, verify, time it, record the fallback.
- **P5 — Polish**: the "real problem" workload, the stage script, and the takeaway (skill users can reuse).

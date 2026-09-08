#!/usr/bin/env bash
# build-skill.sh — package the OCM add-on skill as a standalone, installable
# Agent Skill, entirely off to the side. It READS the demo's SKILL.md + examples
# and GENERATES a self-contained skill folder under dist/. It never modifies the
# source: the YAML frontmatter a real skill needs is *prepended in the generated
# copy only*, so SKILL.md at the repo root stays exactly as the demo uses it.
#
# Output (gitignored):
#   dist/ocm-addon-skill/
#     SKILL.md      <- frontmatter (name/description) + the source SKILL.md body, verbatim
#     examples/     <- the workload manifests SKILL.md references, so it travels self-contained
#     README.md     <- how to install and invoke it
#
# The result is drop-in: copy dist/ocm-addon-skill/ into ~/.claude/skills/ (personal)
# or .claude/skills/ (project), or lift it wholesale into an OCM/skills/ repo.
#
# Usage:
#   ./hack/build-skill.sh          # build dist/ocm-addon-skill/
#   ./hack/build-skill.sh --zip    # also write dist/ocm-addon-skill.zip
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_NAME="ocm-addon-skill"
SRC_SKILL="${REPO_ROOT}/SKILL.md"
SRC_EXAMPLES="${REPO_ROOT}/examples"
DIST="${REPO_ROOT}/dist"
PKG="${DIST}/${SKILL_NAME}"

if [ ! -f "${SRC_SKILL}" ]; then
  echo "Source SKILL.md not found: ${SRC_SKILL}" >&2
  exit 1
fi

# Clean-build just this package (leave anything else in dist/ alone).
rm -rf "${PKG}"
mkdir -p "${PKG}/examples"

# 1) SKILL.md = generated frontmatter + the source body, verbatim (cat, not edited),
#    so the packaged skill always tracks the source on the next rebuild.
{
  cat <<'FRONTMATTER'
---
name: ocm-addon-skill
description: Convert a single-cluster Kubernetes workload (Deployment or DaemonSet) into a template-based Open Cluster Management (OCM) add-on that the hub rolls out fleet-wide. Generates the four objects — AddOnTemplate, AddOnDeploymentConfig, ClusterManagementAddOn, and Placement. Use when someone wants to turn a workload into an OCM add-on, or roll a Deployment/DaemonSet out across an OCM or Red Hat ACM managed-cluster fleet from a single hub apply.
---

FRONTMATTER
  cat "${SRC_SKILL}"
} > "${PKG}/SKILL.md"

# 2) Bundle the example workloads the skill references, so it's self-contained.
if compgen -G "${SRC_EXAMPLES}/*.yaml" > /dev/null; then
  cp "${SRC_EXAMPLES}"/*.yaml "${PKG}/examples/"
fi

# 3) A short install/usage README for whoever receives the package.
cat > "${PKG}/README.md" <<'MD'
# ocm-addon-skill

A standalone [Agent Skill](https://code.claude.com/docs/en/skills) that turns a
single-cluster Kubernetes workload (`Deployment` or `DaemonSet`) into a
**template-based Open Cluster Management (OCM) add-on** the hub rolls out across a
whole managed-cluster fleet — *three objects, one placement, and the hub does the rest.*

It generates the four OCM objects:

1. `AddOnTemplate` — *what to ship.*
2. `AddOnDeploymentConfig` — *how it varies per cluster.*
3. `ClusterManagementAddOn` — *register it + how it rolls out.*
4. `Placement` — *which clusters.*

## Install

Copy this folder into one of Claude Code's skill directories:

```bash
# Personal (available in every project):
cp -R ocm-addon-skill ~/.claude/skills/

# — or — Project-scoped (checked in with a repo):
mkdir -p .claude/skills && cp -R ocm-addon-skill .claude/skills/
```

Then start (or restart) Claude Code so it picks up the new skill.

## Use

Ask for the transformation in plain language — the skill auto-invokes:

> Turn `examples/node-exporter-daemonset.yaml` into an OCM add-on.

A sample workload ships in `examples/` so you can try it immediately; point the skill
at your own `Deployment`/`DaemonSet` the same way. The skill writes the four manifests
to an output directory and prints a summary; apply them to your OCM hub with
`kubectl apply -f <output-dir>/`.

### Modes
- **Interactive (default):** scaffolds one object per turn, explaining each, printing
  the YAML inline — good for learning or presenting.
- **`--quiet` / "all at once":** emits all four manifests with no narration.

## Requirements
- An OCM hub with the `AddonManagement` feature gate (default on), and a `Placement`
  namespace with a bound `ManagedClusterSet` (see the guardrails inside `SKILL.md`).

---
*Generated from the [kubeconSLC26](https://github.com/augustrh/kubeconSLC26) demo
(`make skill`). The source of truth for the skill body is that repo's `SKILL.md`.*
MD

echo "Built ${PKG}/"
echo "  SKILL.md   (frontmatter + source body)"
echo "  examples/  ($(ls -1 "${PKG}/examples" 2>/dev/null | wc -l | tr -d ' ') file(s))"
echo "  README.md  (install + usage)"

# Optional: zip it for sharing.
if [ "${1:-}" = "--zip" ]; then
  if command -v zip > /dev/null 2>&1; then
    ( cd "${DIST}" && rm -f "${SKILL_NAME}.zip" && zip -rq "${SKILL_NAME}.zip" "${SKILL_NAME}" )
    echo "Wrote ${DIST}/${SKILL_NAME}.zip"
  else
    echo "[warn] 'zip' not found — skipping archive; the folder ${PKG}/ is ready to copy." >&2
  fi
fi

echo
echo "Install it:  cp -R ${PKG} ~/.claude/skills/     (then restart Claude Code)"

.PHONY: check-diff test-e2e test-unit images image-push image-manifest image-manifest-annotate image-manifest-push setup-env demo verify showtime showtime-glass diagram skill reset clean

# Number of managed-cluster spokes to create. Override on the command line, e.g.
#   make setup-env NUM_CLUSTERS=3
# setup-env and clean both honor this. (demo/showtime/reset auto-discover spokes
# from the hub, so they adapt to whatever N you built without any flag.)
NUM_CLUSTERS ?= 2

check-diff:
	@git diff --exit-code || (echo "Git working directory is dirty!" && exit 1)

test-unit:
	@echo "No unit tests required for prompt/skill specs."

test-e2e:
	@echo "Testing scaffolding workflow..."
	bash ./hack/setup-env.sh 2

images:
image-push:
image-manifest:
image-manifest-annotate:
image-manifest-push:
	@echo "No container images for this skill project."

setup-env:
	bash ./hack/setup-env.sh $(NUM_CLUSTERS)

demo:
	@# Clean-room every run: if the dir already exists the skill just validates and
	@# narrates the existing files instead of regenerating them. Delete first so the
	@# demo always shows a real build from examples/node-exporter-daemonset.yaml.
	@rm -rf ./ocm-addon-output
	claude --dangerously-skip-permissions "Using SKILL.md, convert ./examples/node-exporter-daemonset.yaml into an OCM addon, interactive presenter-paced mode, output into ./ocm-addon-output"

# Prove the LIVE skill run still produces the known-good bundle. Runs the skill
# in --quiet mode into the gitignored ./ocm-addon-output and diffs it against
# break-glass/ (ignoring that dir's README). Exit 0 = equivalent.
verify:
	@echo "=== Generating a fresh skill run (--quiet, headless) ==="
	@rm -rf ./ocm-addon-output
	claude -p --dangerously-skip-permissions "Using SKILL.md, convert ./examples/node-exporter-daemonset.yaml into an OCM addon, --quiet mode, output into ./ocm-addon-output"
	@echo "=== Diffing live output against break-glass/ ==="
	@if diff -ru --exclude=README.md ./break-glass ./ocm-addon-output; then \
		echo "✅ Live skill output matches break-glass/"; \
	else \
		echo "⚠️  Differences found above. Cosmetic (comments/one-liners) is fine;"; \
		echo "    structural drift means update break-glass/ or fix SKILL.md."; \
		exit 1; \
	fi

# The live-demo deploy button: apply -> watch until Available -> show node-exporter
# pods per spoke, then HOLD on the finished screen (refreshing in place) until you
# press Ctrl-C. No hanging -w; nothing scrolls away on stage. Run after `make demo`.
showtime:
	bash ./hack/showtime.sh ./ocm-addon-output

# Same, but deploy the known-good fallback (for a real on-stage emergency).
showtime-glass:
	bash ./hack/showtime.sh ./break-glass

# Pop up the "meanwhile, the hub is doing the work" diagram as a clean HTML page
# (crisp on a projector, clean background) — regenerated from docs/rollout-diagram.txt,
# the same text showtime.sh prints. Keep this on a second screen during the ~80s rollout.
diagram:
	bash ./hack/render-diagram.sh --open

# Package the skill as a standalone, installable Agent Skill under dist/ (gitignored),
# entirely off to the side — reads SKILL.md + examples/ and generates a self-contained
# folder (frontmatter prepended in the COPY only; the source SKILL.md is never touched).
# Drop dist/ocm-addon-skill/ into ~/.claude/skills/ to try it, or lift it into an
# OCM/skills/ repo. `make skill` builds the folder; `hack/build-skill.sh --zip` also zips it.
skill:
	bash ./hack/build-skill.sh

# Light reset between rehearsals: remove the add-on, KEEP the clusters, so you're
# back to "ready to demo" (clusters up, nothing deployed). Deleting the
# ClusterManagementAddOn cascades to the per-cluster ManagedClusterAddOns and
# ManifestWorks, so the klusterlets pull node-exporter back off the spokes.
# (kubectl -f on a dir only reads .yaml/.yml/.json, so break-glass/README.md is ignored.)
reset:
	@echo "=== Removing the add-on (returning to 'ready to demo') ==="
	kubectl config use-context kind-hub
	@# Delete the add-on resources by name (same in both bundles). Deleting the
	@# ClusterManagementAddOn cascades to the ManagedClusterAddOns + ManifestWorks,
	@# so the workload is pulled off the spokes.
	kubectl delete clustermanagementaddon node-exporter --ignore-not-found
	kubectl delete addontemplate node-exporter --ignore-not-found
	kubectl delete addondeploymentconfig node-exporter -n open-cluster-management --ignore-not-found
	@# The Placement name can differ between the live run and break-glass (AI variance),
	@# so clear ALL placements in default. (The ManagedClusterSetBinding is a different
	@# kind and is left intact.)
	kubectl delete placement --all -n default --ignore-not-found
	@# The hub-side delete returns immediately, but the workload comes off the spokes
	@# asynchronously (ManifestWork GC). Wait until 'monitoring' is actually empty on
	@# every spoke so reset is an honest "ready to demo" signal (60s cap).
	@echo "=== Waiting for node-exporter to clear from the spokes ==="
	@bash ./hack/wait-spokes-clean.sh
	@echo "=== Done. Clusters still up. Confirm the add-on is gone: ==="
	kubectl get managedclusteraddon -A
	@echo "    (and on a spoke: kubectl --context kind-cluster-1 get pods -n monitoring)"

# Full teardown: delete the kind clusters entirely (use when you're finished, not
# between rehearsals). Also removes the live skill output. Deletes the demo's own
# clusters — the hub plus every 'cluster-N' — whatever count you built, matched by
# name so any UNRELATED kind clusters on your machine are left untouched.
clean:
	rm -rf ./ocm-addon-output
	@targets=$$(kind get clusters 2>/dev/null | grep -E '^(hub|cluster-[0-9]+)$$' || true); \
	if [ -n "$$targets" ]; then \
		echo "Deleting kind clusters: $$targets"; \
		kind delete clusters $$targets; \
	else \
		echo "No demo kind clusters (hub / cluster-N) found — nothing to delete."; \
	fi

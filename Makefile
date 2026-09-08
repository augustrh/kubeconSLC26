.PHONY: check-diff test-e2e test-unit images image-push image-manifest image-manifest-annotate image-manifest-push setup-env demo verify showtime showtime-glass reset clean

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
	bash ./hack/setup-env.sh 2

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

# The live-demo deploy button: apply -> watch until Available (self-terminating,
# no hanging -w) -> show node-exporter pods per spoke. Run after `make demo`.
showtime:
	bash ./hack/showtime.sh ./ocm-addon-output

# Same, but deploy the known-good fallback (for a real on-stage emergency).
showtime-glass:
	bash ./hack/showtime.sh ./break-glass

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
# between rehearsals). Also removes the live skill output.
clean:
	rm -rf ./ocm-addon-output
	kind delete clusters hub cluster-1 cluster-2

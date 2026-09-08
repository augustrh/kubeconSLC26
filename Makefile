.PHONY: check-diff test-e2e test-unit images image-push image-manifest image-manifest-annotate image-manifest-push setup-env demo verify reset clean

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

# Light reset between rehearsals: remove the add-on, KEEP the clusters, so you're
# back to "ready to demo" (clusters up, nothing deployed). Deleting the
# ClusterManagementAddOn cascades to the per-cluster ManagedClusterAddOns and
# ManifestWorks, so the klusterlets pull node-exporter back off the spokes.
# (kubectl -f on a dir only reads .yaml/.yml/.json, so break-glass/README.md is ignored.)
reset:
	@echo "=== Removing the add-on (returning to 'ready to demo') ==="
	kubectl config use-context kind-hub
	kubectl delete -f ./break-glass/ --ignore-not-found
	@echo "=== Done. Clusters still up. Confirm the add-on is gone: ==="
	kubectl get managedclusteraddon -A
	@echo "    (and on a spoke: kubectl --context kind-cluster-1 get pods -n monitoring)"

# Full teardown: delete the kind clusters entirely (use when you're finished, not
# between rehearsals). Also removes the live skill output.
clean:
	rm -rf ./ocm-addon-output
	kind delete clusters hub cluster-1 cluster-2

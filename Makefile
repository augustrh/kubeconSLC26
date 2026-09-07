.PHONY: check-diff test-e2e test-unit images image-push image-manifest image-manifest-annotate image-manifest-push setup-env demo clean

check-diff:
	@git diff --exit-code || (echo "Git working directory is dirty!" && exit 1)

test-unit:
	@echo "No unit tests required for prompt/skill specs."

test-e2e:
	@echo "Testing scaffolding workflow..."
	./hack/setup-env.sh 2

images:
image-push:
image-manifest:
image-manifest-annotate:
image-manifest-push:
	@echo "No container images for this skill project."

setup-env:
	./hack/setup-env.sh 2

demo:
	claude --dangerously-skip-permissions "Using SKILL.md, convert ./examples/node-exporter-daemonset.yaml into an OCM addon, interactive presenter-paced mode, output into ./ocm-addon-output"

clean:
	rm -rf ./ocm-addon-output
	kind delete clusters hub cluster-1 cluster-2

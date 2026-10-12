TF_DIR := infra/terraform
SHELL_SRC := $(shell git ls-files '*.sh')

.PHONY: help fmt lint test validate plan apply stop teardown cost preflight

help:            ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

fmt:             ## format terraform + python
	terraform -chdir=$(TF_DIR) fmt -recursive
	ruff format pipeline tests

lint:            ## static checks (same as CI)
	terraform -chdir=$(TF_DIR) fmt -check -recursive
	shellcheck -S warning $(SHELL_SRC)
	ruff check pipeline tests

test:            ## unit tests: pipeline + watchdog logic
	python -m pytest -q tests
	bash ops/watchdog/test-watchdog.sh

validate:        ## terraform validate without a backend
	terraform -chdir=$(TF_DIR) init -backend=false -input=false >/dev/null
	terraform -chdir=$(TF_DIR) validate

preflight:       ## quota / identity / IP checks before spending money
	bash ops/cost/preflight.sh

plan: preflight  ## terraform plan
	terraform -chdir=$(TF_DIR) plan -out=tfplan

apply:           ## apply the saved plan
	terraform -chdir=$(TF_DIR) apply tfplan

stop:            ## stop the GPU node (compute billing ends, EBS stays)
	aws ec2 stop-instances --instance-ids $$(terraform -chdir=$(TF_DIR) output -raw instance_id)

cost:            ## month-to-date gross vs net spend
	bash ops/cost/cost-report.sh

teardown:        ## inventory billable leftovers (add ARGS=--apply to delete)
	bash ops/teardown/teardown.sh $(ARGS)

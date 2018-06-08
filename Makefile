ifneq ($(strip $(AWS_ACCESS_KEY_ID)),)
	aws_id=-e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
endif

ifneq ($(strip $(AWS_SECRET_ACCESS_KEY)),)
	aws_secret=-e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
endif

DEPLOYMENT =

TERRAFORM_RUN = docker run --rm -it \
				-v ${CURDIR}:/work \
				-v $$HOME/.aws:/root/.aws \
				-v $$HOME/.ssh:/root/.ssh \
				-v /var/run/docker.sock:/var/run/docker.sock \
				-v ${CURDIR}/../worker:/triton/worker \
				-v ${CURDIR}/../services:/triton/services \
				${aws_id} \
				${aws_secret} \
				$(2) \
				triton-terraform \
				$(1)

# If using docker run with -t the output will have carriage returns (\r)
# added to it. In some cases (like in print-env-vars) we don't want those
# carriage returns because they end up become part of the env var's value.
# Why does -t added \r? Because Linux TTY: https://github.com/docker/docker/issues/8513
TERRAFORM_RUN_NO_TTY = docker run --rm -i \
				-v ${CURDIR}:/work \
				-v $$HOME/.aws:/root/.aws \
				-v /var/run/docker.sock:/var/run/docker.sock \
				-v ${CURDIR}/../worker:/triton/worker \
				-v ${CURDIR}/../services:/triton/services \
				${aws_id} \
				${aws_secret} \
				$(2) \
				triton-terraform \
				$(1)

.PHONY: help
help:
	@echo "Please use 'make <target>' where <target> is one of"
	@echo "  config        Set up config variables that Terraform needs"
	@echo "  activate      Activate an existing infrastructure config locally:"
	@echo "                  make activate DEPLOYMENT='example'"
	@echo ""
	@echo "  apply         Deploy/update infrastructure"
	@echo "  plan          See what will be deployed/updated"
	@echo "  destroy       Destroy infrastructure"
	@echo "  version       Print terraform version"
	@echo "  taint         Mark a terraform variable as needing update:"
	@echo "                ex: make taint args='-module=triton_host.triton_host aws_launch_configuration.triton-as-conf'"
	@echo ""
	@echo "  apply-api     Deploy/update infrastructure (API only)"
	@echo "  plan-api      See what will be deployed/updated (API only)"
	@echo ""
	@echo "  print-env     Print Triton related shell env variables for exporting"
	@echo "  fmt           Pretty format the Terraform code"

.PHONY: config
config:
	@make terraform.tfvars

.PHONY: activate
activate: build-image
	@test $(DEPLOYMENT) || (echo "usage: make activate DEPLOYMENT=foo" && exit 1)
	@$(call TERRAFORM_RUN,activate --yes $(DEPLOYMENT),--entrypoint /work/scripts/init_tfvars.py)

terraform.tfvars:
	# do not put build-image as a dependency otherwise the tfvars file
	# will be seen as modified every time
	@make build-image
	@$(call TERRAFORM_RUN,new,--entrypoint /work/scripts/init_tfvars.py)

terraform-backend: terraform.tfvars
	@$(call TERRAFORM_RUN,,--entrypoint ./scripts/terraform_s3_backend_provisioner.py)
	# try and find a deployment that has the same name = "..." line... if that
	# exists, then copy this backend.tf file into that folder
	NAME_LINE=$$(grep "^name" terraform.tfvars); \
	DEPLOY_DIR=$$(dirname "$$(grep -Rl "$$NAME_LINE" deployments)"); \
	if [[ ! -z "$$DEPLOY_DIR" && "$$DEPLOY_DIR" != "." ]]; then \
		cp backend.tf "$$DEPLOY_DIR/"; \
	fi;


.PHONY: build-image
build-image:
	docker build -t triton-terraform terraform

.PHONY: fmt
fmt: build-image
# terraform fmt
	@$(call TERRAFORM_RUN,terraform fmt)

.PHONY: init
init: terraform-backend
# Run terraform get to get modules. Init is supposed to do the same, but
# # doesn't seem to work exactly the same
	@$(call TERRAFORM_RUN,terraform get)
# terraform init
	@$(call TERRAFORM_RUN,terraform init)

.PHONY: plan
plan: terraform-backend init
# terraform plan
	@$(call TERRAFORM_RUN,terraform plan)

.PHONY: version 
version: terraform-backend init
	@$(call TERRAFORM_RUN,terraform version)

.PHONY: taint
taint: terraform-backend init
# terraform plan
	@$(call TERRAFORM_RUN,terraform taint $(args))

.PHONY: plan-api
plan-api: terraform-backend init
# terraform plan
	@$(call TERRAFORM_RUN,terraform plan -target=module.triton_api)


.PHONY: apply
apply: terraform-backend init
# terraform apply
	@$(call TERRAFORM_RUN,terraform apply)


.PHONY: apply-api
apply-api: terraform-backend init
	@$(call TERRAFORM_RUN,terraform apply -target=module.triton_api)


.PHONY: destroy
destroy: terraform-backend init
# Store some infra values in files (because no good way to get values into
# a Makefile variable that runs inline in a recipe.
# These values are used after 'terraform destroy' finishes so we can
# clean up resources that Terraform doesn't directly manage.
# Temporarily copy the backend to current dir because output needs it to know how to use the remote backend
	@mkdir -p build
	@$(call TERRAFORM_RUN_NO_TTY,terraform output name > build/destroy_name.txt)
	@$(call TERRAFORM_RUN_NO_TTY,terraform output region > build/destroy_region.txt)
	@$(call TERRAFORM_RUN,terraform destroy)
	@$(call TERRAFORM_RUN,`cat build/destroy_region.txt` triton-`cat build/destroy_name.txt`-,--entrypoint ./scripts/delete_sqs_queues_with_prefix.py)
	@$(call TERRAFORM_RUN,`cat build/destroy_region.txt` triton-`cat build/destroy_name.txt`-,--entrypoint ./scripts/delete_domain_worker_iam_roles.py)
	@rm -f build/destroy_region.txt build/destroy_name.txt


.PHONY: clean
clean:
# Remove Terraform modules from "terraform init"
	-rm -rf .terraform
	-rm -rf build
	-docker rmi $$(docker images -q -f label=net.mediatemple.name=triton-terraform)


.PHONY: shell
shell: build-image
# for debug
	@$(call TERRAFORM_RUN,,--entrypoint sh)

.PHONY: env
env:
# Print environment variables
# Temporarily copy the backend to current dir because output needs it to know how to use the remote backend
	@$(MAKE) --silent -C . build-image 2>/dev/null 1>/dev/null
	@$(call TERRAFORM_RUN,terraform output)


.PHONY: print-env
print-env:
# Print environment variables as export statements
# Can use to set local TRITON_* env variables by running in command line like:
# $(make print-env)
# Temporarily copy the backend to current dir because output needs it to know how to use the remote backend
	@$(MAKE) --silent -C . build-image 2>/dev/null 1>/dev/null
	@$(call TERRAFORM_RUN_NO_TTY,/work/scripts/print_export_env_vars.py)

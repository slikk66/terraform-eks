ifneq ($(strip $(AWS_ACCESS_KEY_ID)),)
	aws_id=-e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
endif

ifneq ($(strip $(AWS_SECRET_ACCESS_KEY)),)
	aws_secret=-e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
endif

DEPLOYMENT =

TERRAFORM_RUN = docker run --rm -it \
				-v ${CURDIR}:/data \
				-v $$HOME/.aws:/root/.aws \
				-v $$HOME/.ssh:/root/.ssh \
				-w=/data \
				${aws_id} \
				${aws_secret} \
				$(2) \
				hashicorp/terraform \
				$(1)

# If using docker run with -t the output will have carriage returns (\r)
# added to it. In some cases (like in print-env-vars) we don't want those
# carriage returns because they end up become part of the env var's value.
# Why does -t added \r? Because Linux TTY: https://github.com/docker/docker/issues/8513
TERRAFORM_RUN_NO_TTY = docker run --rm -i \
				-v ${CURDIR}:/data \
				-v $$HOME/.aws:/root/.aws \
				-w=/data \				
				${aws_id} \
				${aws_secret} \
				$(2) \
				hashicorp/terraform \
				$(1)

.PHONY: init
# terraform init
	@$(call TERRAFORM_RUN, init)

.PHONY: plan
# terraform plan
	@$(call TERRAFORM_RUN, plan)

.PHONY: version 
	@$(call TERRAFORM_RUN, version)

.PHONY: apply
# terraform apply
	@$(call TERRAFORM_RUN, apply)

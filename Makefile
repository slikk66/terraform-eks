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
				-w /data \
				${aws_id} \
				${aws_secret} \
				$(2) \
				hashicorp/terraform \
				$(1)

.PHONY: init
init:
# terraform init
	@$(call TERRAFORM_RUN, init)

.PHONY: plan
plan:
# terraform plan
	@$(call TERRAFORM_RUN, plan)

.PHONY: apply
apply:
# terraform apply
	@$(call TERRAFORM_RUN, apply)

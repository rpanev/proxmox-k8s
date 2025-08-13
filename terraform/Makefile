# Makefile for Terraform

TF      := $(shell terraform --version 2>/dev/null)
TF_INIT := $(shell find .terraform 2>/dev/null)
GREEN   := $(shell tput setaf 2)
RESET   := $(shell tput sgr0)
TF_DOCS := $(shell terraform-docs --version 2>/dev/null)
TFLINT  := $(shell tflint --version 2>/dev/null)

.PHONY: help init plan apply destroy output checks validate-terraform validate-terraform-init validate-tf-docs validate-tflint apply-plan


help: validate-terraform validate-terraform-init validate-tf-docs validate-tflint
	@echo " Available targets: "
	@echo "  ${GREEN}checks${RESET}     : Run formatting, validation, linting, and documentation generation checks."
	@echo "  ${GREEN}init${RESET}       : Initialize Terraform."
	@echo "  ${GREEN}plan${RESET}       : Create a Terraform execution plan."
	@echo "  ${GREEN}apply${RESET}      : Apply Terraform changes."
	@echo "  ${GREEN}apply-plan${RESET} : Apply Terraform changes based on existing plan"
	@echo "  ${GREEN}destroy${RESET}    : Destroy Terraform resources."
	@echo "  ${GREEN}output${RESET}     : Output Terraform state."

validate-terraform:
ifndef TF
	$(error "Terraform is not available. Please install terraform")
endif

validate-terraform-init:
ifndef TF_INIT
	$(error "Please run '${GREEN}terraform init${RESET}'")
endif

validate-tf-docs:
ifndef TF_DOCS
        $(error "${GREEN}terraform-docs${RESET} is not available. Please install terraform-docs")
endif

validate-tflint:
ifndef TFLINT
        $(error "${GREEN}tflint${RESET} is not available. Please install tflint")
endif

checks:
	@echo -n " + Formatting Terraform code"
	@terraform fmt
	@echo " -${GREEN} OK${RESET}"

	@echo -n " + Validating Terraform code"
	@terraform validate 1>/dev/null
	@echo " -${GREEN} OK${RESET}"

	@echo -n " + Generating Terraform docs"
	@terraform-docs markdown table --output-file README.md . 1>/dev/null
	@echo " -${GREEN} OK${RESET}"

	@echo -n " + Running Terraform linter"
	@tflint
	@echo "  -${GREEN} OK${RESET}"


init:
	@echo "${GREEN} + Initializing Terraform${RESET}"
	@terraform init

plan:
	@echo "${GREEN} + Creating Terraform execution plan${RESET}"
	@terraform plan -out=terraform.plan

apply:
	@echo "${GREEN} + Applying Terraform changes${RESET}"
	@terraform apply

apply-plan:
	@echo "${GREEN} + Applying saved Terraform plan${RESET}"
	@terraform apply "terraform.plan"

destroy:
	@echo "${GREEN} + Destroying Terraform resources${RESET}"
	@terraform destroy

output:
	@echo "${GREEN} + Outputting Terraform state${RESET}"
	@terraform output

# Set the default target to 'help'
.DEFAULT_GOAL := help
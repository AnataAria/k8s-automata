.PHONY: help aws-plan aws-apply aws-destroy proxmox-plan proxmox-apply proxmox-destroy clean

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

aws-plan: ## Plan AWS infrastructure
	./setup-k8s.sh aws plan

aws-apply: ## Deploy AWS infrastructure and Kubernetes
	./setup-k8s.sh aws apply

aws-destroy: ## Destroy AWS infrastructure
	./setup-k8s.sh aws destroy

aws-ansible: ## Run Ansible on existing AWS infrastructure
	./setup-k8s.sh aws ansible

proxmox-plan: ## Plan Proxmox infrastructure
	./setup-k8s.sh proxmox plan

proxmox-apply: ## Deploy Proxmox infrastructure and Kubernetes
	./setup-k8s.sh proxmox apply

proxmox-destroy: ## Destroy Proxmox infrastructure
	./setup-k8s.sh proxmox destroy

proxmox-ansible: ## Run Ansible on existing Proxmox infrastructure
	./setup-k8s.sh proxmox ansible

both-apply: ## Deploy on both AWS and Proxmox
	./setup-k8s.sh both apply

both-destroy: ## Destroy both AWS and Proxmox infrastructure
	./setup-k8s.sh both destroy

both-ansible: ## Run Ansible on both platforms
	./setup-k8s.sh both ansible

clean: ## Clean temporary files
	find . -name "*.tfstate*" -delete
	find . -name ".terraform*" -delete
	rm -f /tmp/kubernetes-join-command

check-deps: ## Check if required dependencies are installed
	@command -v terraform >/dev/null 2>&1 || { echo "Terraform is required but not installed."; exit 1; }
	@command -v ansible >/dev/null 2>&1 || { echo "Ansible is required but not installed."; exit 1; }
	@echo "All dependencies are installed."

setup-aws: ## Setup AWS configuration files
	cp terraform/aws/terraform.tfvars.example terraform/aws/terraform.tfvars
	@echo "Edit terraform/aws/terraform.tfvars with your configuration"

setup-proxmox: ## Setup Proxmox configuration files
	cp terraform/proxmox/terraform.tfvars.example terraform/proxmox/terraform.tfvars
	@echo "Edit terraform/proxmox/terraform.tfvars with your configuration"

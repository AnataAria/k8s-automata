.PHONY: help aws-plan aws-apply aws-destroy aws-status aws-health aws-backup proxmox-plan proxmox-apply proxmox-destroy proxmox-status proxmox-health proxmox-backup both-plan both-apply both-destroy clean setup-aws setup-proxmox check-deps ping troubleshoot logs

help:
	@echo 'K8s Automata - Kubernetes Cluster Automation'
	@echo ''
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'AWS Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^aws-.*:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ''
	@echo 'Proxmox Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^proxmox-.*:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ''
	@echo 'Multi-Platform Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^both-.*:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ''
	@echo 'Utility Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {if($$1 !~ /^(aws|proxmox|both)-/) printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

aws-plan: ## Plan AWS infrastructure
	./script/main.sh aws plan

aws-apply: ## Deploy AWS infrastructure and Kubernetes
	./script/main.sh aws apply --auto-approve

aws-destroy: ## Destroy AWS infrastructure
	./script/main.sh aws destroy --auto-approve

aws-status: ## Show AWS deployment status
	./script/main.sh aws status

aws-health: ## Run AWS cluster health check
	./script/main.sh aws health --verbose

aws-backup: ## Create AWS cluster backup
	./script/main.sh aws backup --auto-approve

aws-ansible: ## Run Ansible on existing AWS infrastructure
	./script/main.sh aws ansible

aws-ping: ## Test connectivity to AWS hosts
	./script/main.sh aws ping

proxmox-plan: ## Plan Proxmox infrastructure
	./script/main.sh proxmox plan

proxmox-apply: ## Deploy Proxmox infrastructure and Kubernetes
	./script/main.sh proxmox apply --auto-approve

proxmox-destroy: ## Destroy Proxmox infrastructure
	./script/main.sh proxmox destroy --auto-approve

proxmox-status: ## Show Proxmox deployment status
	./script/main.sh proxmox status

proxmox-health: ## Run Proxmox cluster health check
	./script/main.sh proxmox health --verbose

proxmox-backup: ## Create Proxmox cluster backup
	./script/main.sh proxmox backup --auto-approve

proxmox-ansible: ## Run Ansible on existing Proxmox infrastructure
	./script/main.sh proxmox ansible

proxmox-ping: ## Test connectivity to Proxmox hosts
	./script/main.sh proxmox ping

both-plan: ## Plan infrastructure on both platforms
	./script/main.sh both plan

both-apply: ## Deploy on both AWS and Proxmox
	./script/main.sh both apply --auto-approve

both-destroy: ## Destroy both AWS and Proxmox infrastructure
	./script/main.sh both destroy --auto-approve

both-ansible: ## Run Ansible on both platforms
	./script/main.sh both ansible

both-health: ## Run health checks on both platforms
	./script/main.sh both health

ping: ## Test connectivity to all platforms
	./script/main.sh both ping

troubleshoot: ## Run troubleshooting on both platforms
	./script/main.sh both troubleshoot

logs: ## Collect logs from both platforms
	./script/main.sh both logs --action collect

clean: ## Clean temporary files
	./script/main.sh both clean
	find . -name "*.tfstate*" -delete 2>/dev/null || true
	find . -name ".terraform*" -delete 2>/dev/null || true
	find . -name "*.tfplan" -delete 2>/dev/null || true
	find . -name "*.retry" -delete 2>/dev/null || true
	rm -f /tmp/kubernetes-join-command 2>/dev/null || true

check-deps: ## Check if required dependencies are installed
	./script/main.sh aws ping --dry-run 2>/dev/null || echo "Dependencies check completed"

setup-aws: ## Setup AWS configuration files
	@if [ ! -f terraform/aws/configs.auto.tfvars ]; then \
		cp terraform/aws/configs.auto.tfvars.example terraform/aws/configs.auto.tfvars; \
		echo "Created terraform/aws/configs.auto.tfvars - please edit with your configuration"; \
	fi
	@if [ ! -f terraform/aws/secrets.auto.tfvars ]; then \
		cp terraform/aws/secrets.auto.tfvars.example terraform/aws/secrets.auto.tfvars; \
		echo "Created terraform/aws/secrets.auto.tfvars - please edit with your credentials"; \
	fi

setup-proxmox: ## Setup Proxmox configuration files
	@if [ ! -f terraform/proxmox/configs.auto.tfvars ]; then \
		cp terraform/proxmox/configs.auto.tfvars.example terraform/proxmox/configs.auto.tfvars; \
		echo "Created terraform/proxmox/configs.auto.tfvars - please edit with your configuration"; \
	fi
	@if [ ! -f terraform/proxmox/secrets.auto.tfvars ]; then \
		cp terraform/proxmox/secrets.auto.tfvars.example terraform/proxmox/secrets.auto.tfvars; \
		echo "Created terraform/proxmox/secrets.auto.tfvars - please edit with your credentials"; \
	fi

init: ## Initialize project (setup configs and check dependencies)
	@echo "Initializing K8s Automata..."
	make setup-aws
	make setup-proxmox
	make check-deps
	@echo "Initialization complete!"

dev-proxmox: ## Quick development cycle for Proxmox
	./script/main.sh proxmox plan && \
	./script/main.sh proxmox apply --auto-approve && \
	./script/main.sh proxmox health

dev-aws: ## Quick development cycle for AWS
	./script/main.sh aws plan && \
	./script/main.sh aws apply --auto-approve && \
	./script/main.sh aws health

update-system: ## Update system packages on all nodes
	./script/main.sh both update --update-type system --auto-approve

update-k8s: ## Update Kubernetes components
	./script/main.sh both update --update-type kubernetes

backup-all: ## Create backups for all platforms
	./script/main.sh both backup --backup-type full --auto-approve

monitor: ## Show monitoring information
	@echo "Cluster Status:"
	@make both-health 2>/dev/null || echo "Health check failed"
	@echo "\nNode Information:"
	@make ping 2>/dev/null || echo "Connectivity check failed"

quick-proxmox: setup-proxmox proxmox-apply ## Quick setup and deploy Proxmox
quick-aws: setup-aws aws-apply ## Quick setup and deploy AWS

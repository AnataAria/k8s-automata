.PHONY: help aws-plan aws-apply aws-destroy aws-status aws-health aws-backup aws-ansible aws-ping proxmox-plan proxmox-apply proxmox-destroy proxmox-status proxmox-health proxmox-backup proxmox-ansible proxmox-ping both-plan both-apply both-destroy both-ansible both-health ping troubleshoot logs clean setup-aws setup-proxmox check-deps init dev-proxmox dev-aws update-system update-k8s backup-all monitor quick-proxmox quick-aws full-deploy-proxmox full-deploy-aws lb-deploy lb-deploy-aws lb-deploy-proxmox lb-health lb-health-aws lb-health-proxmox lb-restart lb-restart-aws lb-restart-proxmox lb-status lb-status-aws lb-status-proxmox lb-logs lb-logs-aws lb-logs-proxmox lb-config lb-config-aws lb-config-proxmox lb-ping lb-ping-aws lb-ping-proxmox

ANSIBLE_PLAYBOOK ?= site.yml
PLATFORM ?= proxmox
LB_GROUP := load_balancers
LB_SERVICE := haproxy
LB_CONFIG := /etc/haproxy/haproxy.cfg

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
	./script/main.sh aws ansible --playbook $(ANSIBLE_PLAYBOOK)

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
	./script/main.sh proxmox ansible --playbook $(ANSIBLE_PLAYBOOK)

proxmox-ping: ## Test connectivity to Proxmox hosts
	./script/main.sh proxmox ping

lb-deploy: ## Configure load balancers only for the selected platform
	cd ansible && ansible-playbook -i inventories/$(PLATFORM)/hosts.ini $(ANSIBLE_PLAYBOOK) --limit $(LB_GROUP)

lb-deploy-aws: ## Configure AWS load balancers
	$(MAKE) lb-deploy PLATFORM=aws

lb-deploy-proxmox: ## Configure Proxmox load balancers
	$(MAKE) lb-deploy PLATFORM=proxmox

lb-health: ## Check HAProxy health on load balancers for the selected platform
	cd ansible && ansible $(LB_GROUP) -i inventories/$(PLATFORM)/hosts.ini -m shell -a "systemctl is-active $(LB_SERVICE) && ss -lntp | grep -E ':6443\\b'" -b

lb-health-aws: ## Check AWS load balancer health
	$(MAKE) lb-health PLATFORM=aws

lb-health-proxmox: ## Check Proxmox load balancer health
	$(MAKE) lb-health PLATFORM=proxmox

lb-restart: ## Restart HAProxy service on load balancers for the selected platform
	cd ansible && ansible $(LB_GROUP) -i inventories/$(PLATFORM)/hosts.ini -m systemd -a "name=$(LB_SERVICE) state=restarted" -b

lb-restart-aws: ## Restart AWS load balancers
	$(MAKE) lb-restart PLATFORM=aws

lb-restart-proxmox: ## Restart Proxmox load balancers
	$(MAKE) lb-restart PLATFORM=proxmox

lb-status: ## Show HAProxy service status on load balancers for the selected platform
	cd ansible && ansible $(LB_GROUP) -i inventories/$(PLATFORM)/hosts.ini -m systemd -a "name=$(LB_SERVICE)" -b

lb-status-aws: ## Show AWS load balancer status
	$(MAKE) lb-status PLATFORM=aws

lb-status-proxmox: ## Show Proxmox load balancer status
	$(MAKE) lb-status PLATFORM=proxmox

lb-logs: ## View HAProxy logs on load balancers for the selected platform
	cd ansible && ansible $(LB_GROUP) -i inventories/$(PLATFORM)/hosts.ini -m shell -a "journalctl -u $(LB_SERVICE) --no-pager -n 50" -b

lb-logs-aws: ## View AWS load balancer logs
	$(MAKE) lb-logs PLATFORM=aws

lb-logs-proxmox: ## View Proxmox load balancer logs
	$(MAKE) lb-logs PLATFORM=proxmox

lb-config: ## View current HAProxy configuration on load balancers for the selected platform
	cd ansible && ansible $(LB_GROUP) -i inventories/$(PLATFORM)/hosts.ini -m shell -a "cat $(LB_CONFIG)" -b

lb-config-aws: ## View AWS HAProxy configuration
	$(MAKE) lb-config PLATFORM=aws

lb-config-proxmox: ## View Proxmox HAProxy configuration
	$(MAKE) lb-config PLATFORM=proxmox

lb-ping: ## Test connectivity to load balancers for the selected platform
	cd ansible && ansible $(LB_GROUP) -i inventories/$(PLATFORM)/hosts.ini -m ping

lb-ping-aws: ## Test connectivity to AWS load balancers
	$(MAKE) lb-ping PLATFORM=aws

lb-ping-proxmox: ## Test connectivity to Proxmox load balancers
	$(MAKE) lb-ping PLATFORM=proxmox

both-plan: ## Plan infrastructure on both platforms
	./script/main.sh both plan

both-apply: ## Deploy on both AWS and Proxmox
	./script/main.sh both apply --auto-approve

both-destroy: ## Destroy both AWS and Proxmox infrastructure
	./script/main.sh both destroy --auto-approve

both-ansible: ## Run Ansible on both platforms
	./script/main.sh both ansible --playbook $(ANSIBLE_PLAYBOOK)

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
		cp terraform/aws/terraform.tfvars.example terraform/aws/configs.auto.tfvars; \
		echo "Created terraform/aws/configs.auto.tfvars - please edit with your configuration"; \
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
	$(MAKE) setup-aws
	$(MAKE) setup-proxmox
	$(MAKE) check-deps
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

update-k8s: ## Review Kubernetes component versions on all platforms
	./script/main.sh both update --update-type kubernetes

backup-all: ## Create backups for all platforms
	./script/main.sh both backup --backup-type full --auto-approve

monitor: ## Show monitoring information
	@echo "Cluster Status:"
	@$(MAKE) both-health 2>/dev/null || echo "Health check failed"
	@echo "\nNode Information:"
	@$(MAKE) ping 2>/dev/null || echo "Connectivity check failed"

quick-proxmox: setup-proxmox proxmox-apply ## Quick setup and deploy Proxmox
quick-aws: setup-aws aws-apply ## Quick setup and deploy AWS

full-deploy-proxmox: ## Full Proxmox deployment including load balancers
	$(MAKE) proxmox-apply && $(MAKE) lb-deploy-proxmox && $(MAKE) lb-health-proxmox

full-deploy-aws: ## Full AWS deployment including load balancers
	$(MAKE) aws-apply && $(MAKE) lb-deploy-aws && $(MAKE) lb-health-aws
